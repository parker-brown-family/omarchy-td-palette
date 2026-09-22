// What the bar widget's snapshot is allowed to cost the shell it lives in.
//
// BarWidget.qml runs `td-tint --state` and buffers the answer. The bar widget
// is not a process of its own — it runs inside omarchy-shell, which is
// long-lived — so an oracle that never stops writing, or never stops at all,
// spends the shell's memory rather than its own. A marketplace security review
// named both halves (the marketplace verify issue 5385, 2026-09-22):
// the collector fully buffered the producer, and the watchdog neither capped
// producer bytes nor terminated a stalled process.
//
// WHAT THIS FILE IS FOR. The fix rests on one non-obvious, version-dependent
// fact about Quickshell: StdioCollector reports its length while filling ONLY
// when waitForEnd is false. If that ever changes, the ceiling in the widget
// stops being enforceable against the producer and nothing else would say so —
// the widget would still parse, still lint, still pass every static check, and
// quietly go back to buffering without limit. So the platform assumption is
// pinned here, in both directions, against a real runaway.
//
// It does not load BarWidget.qml: a bar widget needs the shell's own
// singletons and a bar to live in, so there is no headless way to summon it.
// bin/verify asserts separately that the widget still uses these constructs.
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
  property int ticksOpen: 0             // waitForEnd:false, runaway
  property int ticksSealed: 0           // waitForEnd:true,  runaway
  property bool capFired: false
  property bool docComplete: false
  property bool docParsed: false

  function check(label, cond, detail) {
    console.log((cond ? "  ok   " : "  FAIL ") + label
                + (cond || !detail ? "" : " — " + detail))
    if (!cond) probe.fails++
  }

  // 1 — a producer that never stops, collected the way the widget collects.
  //     The length has to be visible WHILE it fills, or there is nothing to
  //     cap; and crossing the ceiling has to end the producer.
  Process {
    id: runaway
    running: true
    command: ["yes", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]
    stdout: StdioCollector {
      id: openBuf
      waitForEnd: false
      onDataChanged: {
        probe.ticksOpen++
        if (!probe.capFired && openBuf.text.length > probe.ceiling) {
          probe.capFired = true
          runaway.signal(15)
          killer.restart()
        }
      }
    }
  }
  Timer {
    id: killer
    interval: 500
    onTriggered: if (runaway.running) runaway.signal(9)
  }

  // 2 — the same runaway, sealed. This is the mode the widget used to use, and
  //     the one that makes a byte cap impossible: it is expected to report
  //     NOTHING while filling. A failure here is good news about Quickshell and
  //     means the widget could go back to waitForEnd — read the comment there.
  Process {
    id: sealed
    running: true
    command: ["yes", "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"]
    stdout: StdioCollector {
      waitForEnd: true
      onDataChanged: probe.ticksSealed++
    }
  }

  // 3 — and none of that may cost completeness: a finite producer still has to
  //     deliver its whole document, intact enough to parse.
  Process {
    id: finite
    running: true
    command: ["printf", "{\"tiles\":[],\"monitor\":{},\"ok\":true}"]
    stdout: StdioCollector {
      id: finiteBuf
      waitForEnd: false
      onStreamFinished: {
        probe.docComplete = finiteBuf.text.length > 0
        try {
          probe.docParsed = !!JSON.parse(finiteBuf.text).ok
        } catch (e) {
          probe.docParsed = false
        }
      }
    }
  }

  Timer {
    interval: 4000
    running: true
    onTriggered: {
      console.log("")
      console.log("the snapshot cannot outspend the shell")
      probe.check("an unsealed collector reports its length while filling",
                  probe.ticksOpen > 0, "no dataChanged in 4s")
      probe.check("so a runaway producer trips the " + probe.ceiling + "-byte ceiling",
                  probe.capFired, "never reached the ceiling")
      probe.check("and is ended rather than left writing",
                  !runaway.running, "still running after SIGTERM and SIGKILL")
      probe.check("a sealed collector reports nothing until the end, which is why it is not used",
                  probe.ticksSealed === 0,
                  "it ticked " + probe.ticksSealed + " times — the platform may have changed")
      probe.check("a finite producer still delivers its whole document",
                  probe.docComplete, "streamFinished never landed")
      probe.check("and the document still parses",
                  probe.docParsed, "JSON.parse failed on the delivered text")
      console.log("")
      if (probe.fails > 0) {
        console.log(probe.fails + " snapshot-limit check(s) failed")
        Qt.exit(1)
      }
      console.log("the ceiling holds, and the producer is stoppable")
      Qt.exit(0)
    }
  }
}
