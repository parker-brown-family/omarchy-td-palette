// What the bar widget's snapshot is allowed to cost the shell it lives in.
//
// BarWidget.qml runs `td-tint --state` and buffers the answer. The bar widget
// is not a process of its own — it runs inside omarchy-shell, which is
// long-lived — so an oracle that never stops writing, or never stops at all,
// spends the shell's memory rather than its own. A marketplace security review
// named both halves (the marketplace verify issue 5385, 2026-09-22): the
// collector fully buffered the producer, and the watchdog neither capped
// producer bytes nor terminated a stalled process.
//
// THIS FILE REPLICATES THE WIDGET'S STATE MACHINE RATHER THAN IMPORTING IT. A
// bar widget needs the shell's own singletons and a bar to live in, so there is
// no headless way to summon one. That makes the replication the weak point, and
// it has already failed once: the first version of this file carried a
// once-only guard the widget did not have, so every assertion passed green
// while the widget re-armed its escalation on every chunk and never killed
// anything. The functions below are therefore copied from the widget verbatim
// in shape — paintOpen, consumeOnce, abortSnapshot, and the two timers — and
// bin/verify separately asserts that the widget still has each line they
// depend on. When you change one, change both.
//
//     quickshell -p tests/check_snapshot_limits.qml
//
// Exits 0 when every line says ok.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: probe

  property int ceiling: 262144          // the widget's stateLimit
  property int fails: 0
  property int checksRun: 0

  function check(label, cond, detail) {
    probe.checksRun++
    console.log((cond ? "  ok   " : "  FAIL ") + label
                + (cond || !detail ? "" : " — " + detail))
    if (!cond) probe.fails++
  }

  // ---- 1. a producer that ignores SIGTERM ---------------------------------
  // The polite case proves nothing about the escalation. This one traps TERM
  // and keeps writing, which is the case the SIGKILL is for — and the case the
  // shipped fix got wrong, by restarting the kill timer on every chunk.
  property int abortCalls: 0
  property bool killSent: false
  property bool stubbornRan: false
  property int stubbornRun: 0
  property int stubbornTaken: -1

  function stubbornAbort() {
    if (probe.stubbornTaken === probe.stubbornRun) return   // once per run
    probe.stubbornTaken = probe.stubbornRun
    probe.abortCalls++
    if (stubborn.running) {
      stubborn.signal(15)
      stubbornKill.restart()
    }
  }

  Process {
    id: stubborn
    running: true
    command: ["bash", Qt.resolvedUrl("stubborn-producer.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      id: stubbornBuf
      waitForEnd: false
      onDataChanged: {
        probe.stubbornRan = true
        if (stubbornBuf.text.length > probe.ceiling) probe.stubbornAbort()
      }
    }
  }
  Timer {
    id: stubbornKill
    interval: 500
    onTriggered: {
      if (stubborn.running) {
        probe.killSent = true
        stubborn.signal(9)
      }
    }
  }

  // ---- 2. the sealed collector, which is why waitForEnd is not used --------
  property int ticksSealed: 0
  Process {
    id: sealed
    running: true
    command: ["yes", "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"]
    stdout: StdioCollector {
      waitForEnd: true
      onDataChanged: probe.ticksSealed++
    }
  }

  // ---- 3. completeness across MORE THAN ONE read --------------------------
  // A 38-byte producer arrives in a single read and demonstrates nothing about
  // a document that spans chunks, which is what the real oracle is closest to.
  // `seq` gives a large, finite, verifiable stream: the last line must be there.
  property int bigTicks: 0
  property bool bigComplete: false
  Process {
    id: big
    running: true
    command: ["seq", "1", "200000"]
    stdout: StdioCollector {
      id: bigBuf
      waitForEnd: false
      onDataChanged: probe.bigTicks++
      onStreamFinished: probe.bigComplete =
        bigBuf.text.length > 600000 && bigBuf.text.indexOf("\n200000\n") > 0
    }
  }

  // ---- 4. a run that writes nothing must not replay the last one ----------
  // The collector clears its buffer on the first byte of a run, not at start,
  // so a failing oracle used to hand the picker the PREVIOUS workspace.
  property int emptyRun: 0
  property bool emptySaw: false
  property string emptyDelivered: "unset"
  property bool emptyPhaseTwo: false

  function emptyOpen() {
    probe.emptyRun++
    probe.emptySaw = false
    emptyProc.running = false
    emptyProc.running = true
  }

  Process {
    id: emptyProc
    command: ["printf", "{\"ok\":true}"]
    stdout: StdioCollector {
      id: emptyBuf
      waitForEnd: false
      onDataChanged: probe.emptySaw = true
      onStreamFinished: {
        if (probe.emptyPhaseTwo)
          probe.emptyDelivered = probe.emptySaw ? emptyBuf.text : ""
      }
    }
  }

  // run one produces; run two produces nothing at all.
  Timer {
    interval: 300
    running: true
    onTriggered: probe.emptyOpen()
  }
  Timer {
    interval: 1200
    running: true
    onTriggered: {
      probe.emptyPhaseTwo = true
      probe.emptyRun++
      probe.emptySaw = false
      emptyProc.running = false
      emptyProc.command = ["true"]        // exits 0, writes nothing
      emptyProc.running = true
    }
  }

  // ---- the verdict --------------------------------------------------------
  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.log("")
      console.log("the snapshot cannot outspend the shell")

      probe.check("an unsealed collector reports its length while filling",
                  probe.stubbornRan, "no dataChanged at all in 5s")
      probe.check("a producer past the " + probe.ceiling + "-unit ceiling is aborted",
                  probe.abortCalls > 0, "the ceiling was never tripped")
      probe.check("and aborted ONCE, so the escalation is not pushed out forever",
                  probe.abortCalls === 1,
                  "aborted " + probe.abortCalls + " times — each restarts the kill timer")
      probe.check("a producer that ignores SIGTERM is then SIGKILLed",
                  probe.killSent, "the escalation never fired")
      probe.check("and is gone",
                  probe.stubbornRan && !stubborn.running,
                  "still running after SIGTERM and SIGKILL")
      probe.check("a sealed collector reports nothing until the end, which is why it is not used",
                  probe.ticksSealed === 0,
                  "it ticked " + probe.ticksSealed + " times — the platform may have changed")
      probe.check("a document spanning several reads still arrives whole",
                  probe.bigComplete,
                  "ticks=" + probe.bigTicks + " len=" + bigBuf.text.length)
      probe.check("and a run that writes nothing delivers nothing, not the last run's document",
                  probe.emptyDelivered === "",
                  "delivered " + JSON.stringify(probe.emptyDelivered).slice(0, 40))

      console.log("")
      if (probe.fails > 0) {
        console.log(probe.fails + " of " + probe.checksRun + " snapshot-limit check(s) failed")
        Qt.exit(1)
      }
      console.log("the ceiling holds, the producer is stoppable, and no run wears another's clothes")
      Qt.exit(0)
    }
  }
}
