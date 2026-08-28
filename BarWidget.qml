import QtQuick
import Quickshell.Io
import qs.Ui

// Terminal Paint — the painter's palette in the tray.
//
// This widget is a doorbell, not a panel. Wayland forbids one client painting
// into another client's surface, so the overlay itself — a glyph grid over
// every terminal pane, click a glyph to recolour that pane — is rendered by
// terminal-delight inside its own windows. All the button does is ring the
// terminal's control socket through the binary already on PATH:
// `terminal-delight ctl paint …`. One short-lived process per click, nothing
// resident, nothing polled, and the widget stays correct however many
// terminals come and go.
BarWidget {
  id: root
  moduleName: "brownfamilysports.td-palette"

  // A failed ring means no paintable terminal answered — either none on this
  // workspace, or one from a build without the ctl socket. Say so on the face
  // for a moment instead of failing silently; a blink is honest and cheap
  // where a dialog would be noise.
  property bool missing: false

  // The vertical bar needs no second face (taste-ok: vertical): the whole
  // surface is one emoji glyph, equally legible in either orientation, and
  // WidgetButton already sizes its slot per bar.vertical. A widget with words
  // would need the clock's second format ring; a brush does not.

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function ctl(args) {
    // One in-flight call at a time: painting is a human-speed action, and a
    // re-click before the last call lands should replace it, not queue it.
    runner.running = false
    runner.command = ["terminal-delight", "ctl"].concat(args)
    runner.running = true
  }

  Process {
    id: runner
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    // The signature is verified against quickshell-io.qmltypes: exited(int,
    // QProcess::ExitStatus). The second type is a C++ enum with no QML
    // registration, so the linter cannot resolve it — that is the linter's
    // blind spot, not a wrong handler, hence the targeted disable.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.missing = true
        unmiss.restart()
      }
    }
    // qmllint enable signal-handler-parameters
  }

  // One-shot feedback reset — not a poll; it only ever runs after a miss.
  Timer {
    id: unmiss
    interval: 1600
    onTriggered: root.missing = false
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.missing ? "🖌∅" : "🎨"
    tooltipText: "Paint terminals — left: this workspace · middle: everywhere · right: done painting"

    // Left paints HERE (the workspace you are looking at), middle paints the
    // whole wall on every workspace, right lowers every brush — three
    // buttons, three meanings (TASTE rule 9).
    onPressed: function (b) {
      if (b === Qt.LeftButton) root.ctl(["paint", "toggle"])
      else if (b === Qt.MiddleButton) root.ctl(["paint", "toggle", "--all"])
      else if (b === Qt.RightButton) root.ctl(["paint", "off", "--all"])
    }
  }

  // The keyboard-first path: `omarchy-shell brownfamilysports.td-palette
  // toggle` from a Hyprland bind does what a left click does. open/close map
  // to paint on/off so the verbs read the same as every popup widget's.
  IpcHandler {
    target: "brownfamilysports.td-palette"

    function toggle(): void { root.ctl(["paint", "toggle"]) }
    function open(): void { root.ctl(["paint", "on"]) }
    function close(): void { root.ctl(["paint", "off", "--all"]) }
  }
}
