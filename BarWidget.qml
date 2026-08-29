import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The linter cannot see Quickshell's C++ type registration (PanelWindow reads
// as uncreatable) nor the dynamic members of the theme singletons
// (Color.menu.*, Style.font.* read as missing) — first-party Emojis.qml scores
// 50 warnings in exactly these three categories under the identical
// invocation, so this is the tool's blind spot, not this file's. Disabled
// file-wide below; every other check still runs.
// qmllint disable uncreatable-type missing-property unqualified

// Terminal Paint — the painter's palette in the tray, and the workspace
// overlay it raises: Terminal Delight's "PAINT THIS PANE" picker, floated
// over every terminal TILE on the active workspace.
//
// The shell cannot paint inside another client, but it can float a layer
// above the tiling and put a card in the middle of each terminal window. A
// card click aims `td-tint --window <address> <variant>` at that window — OSC
// palette down its tty, matching border on its frame — so foot, Alacritty,
// kitty and friends get the same one-click identity Terminal Delight panes
// have. Terminal Delight windows are the one exception: this layer would sit
// ON TOP of their own per-pane picker and steal its input, so their card is a
// single handoff — raise the in-app picker over ctl and get out of the way.
//
// Everything lives in this ONE file on purpose: the QML engine currently
// refuses to load a second .qml entry point from a third-party plugin dir
// ("File name case mismatch", even for a minimal Item — see the lab issue),
// while the bar-widget entry loads fine. One file, one load path, and the
// widget talks to its own overlay by plain function call instead of
// round-tripping through shell IPC.
BarWidget {
  id: root
  moduleName: "brownfamilysports.td-palette"

  // The vertical bar needs no second face (taste-ok: vertical): the whole
  // surface is one emoji glyph, equally legible in either orientation, and
  // WidgetButton already sizes its slot per bar.vertical.

  // The popup contract (Bar.findPanelWidget): opened/open/close on the root
  // is what makes `omarchy-shell shell summon|hide|toggle <id>` — and with it
  // any Hyprland keybind — reach this widget.
  property bool opened: false
  function open() { root.paintOpen() }
  function close() { root.paintDismiss(false) }

  // What a summon snapshot found: installed variants and the terminal tiles
  // (monitor-local rects) of the active workspace.
  property var variants: []

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function paintOpen() {
    console.log("td-paint: open — snapshotting")
    snapshot.running = false
    snapshot.running = true
  }

  // keepTd: a handoff card just raised Terminal Delight's own picker — leave
  // it standing. Every other dismissal folds the whole painting session.
  function paintDismiss(keepTd) {
    root.opened = false
    if (!keepTd)
      Quickshell.execDetached(["terminal-delight", "ctl", "paint", "off", "--all"])
  }

  function paintToggle() {
    if (root.opened) root.paintDismiss(false)
    else root.paintOpen()
  }

  // One process, one snapshot: the variant list and the compositor state,
  // fetched at summon time. No polling — the picker sees the workspace as it
  // was when you rang it, which is also the workspace you were looking at.
  Process {
    id: snapshot
    command: ["bash", "-c",
      "td-tint --json; echo @@; hyprctl -j activeworkspace; echo @@; hyprctl -j clients; echo @@; hyprctl -j monitors"]
    stdout: StdioCollector { id: snapText }
    // Verified against quickshell-io.qmltypes: exited(int, QProcess::ExitStatus).
    // The enum has no QML registration — linter blind spot, not a wrong handler.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, exitStatus) {
      collectDelay.restart()
    }
    // qmllint enable signal-handler-parameters
  }

  // The collectors drain a beat after the exit signal — read them then.
  Timer {
    id: collectDelay
    interval: 120
    onTriggered: root.consume(snapText.text)
  }

  function consume(raw) {
    var parts = raw.split("@@")
    console.log("td-paint: snapshot " + raw.length + " bytes, " + parts.length + " parts")
    if (parts.length < 4) return
    var vars, aws, clients, mons
    try {
      vars = JSON.parse(parts[0])
      aws = JSON.parse(parts[1])
      clients = JSON.parse(parts[2])
      mons = JSON.parse(parts[3])
    } catch (e) {
      console.log("td-paint: snapshot parse failed: " + e)
      return
    }
    var mon = null
    for (var i = 0; i < mons.length; i++) if (mons[i].focused) mon = mons[i]
    if (!mon && mons.length > 0) mon = mons[0]
    if (!mon) return

    // Terminals we can reach over OSC. Terminal Delight is deliberately not
    // in this map — it has a better story (per-pane, persistent) via ctl.
    var OSC_TERMS = {
      "foot": 1, "Alacritty": 1, "kitty": 1,
      "com.mitchellh.ghostty": 1, "org.wezfurlong.wezterm": 1
    }
    tileModel.clear()
    var oscCount = 0
    var anyTd = false
    for (var c = 0; c < clients.length; c++) {
      var w = clients[c]
      if (!w.workspace || w.workspace.id !== aws.id) continue
      var isTd = w.class === "terminal-delight"
      if (!isTd && !OSC_TERMS[w.class]) continue
      if (isTd) anyTd = true
      else oscCount++
      tileModel.append({
        address: w.address,
        pid: w.pid,
        td: isTd,
        tx: w.at[0] - mon.x,
        ty: w.at[1] - mon.y,
        tw: w.size[0],
        th: w.size[1]
      })
    }
    root.variants = vars

    if (oscCount === 0 && anyTd) {
      // A pure Terminal Delight workspace needs no layer at all — hand the
      // whole gesture to the in-app per-pane picker and stay invisible.
      Quickshell.execDetached(["terminal-delight", "ctl", "paint", "on"])
      return
    }
    if (tileModel.count === 0) {
      Quickshell.execDetached(["notify-send", "-a", "Terminal Paint", "-e",
        "Nothing to paint", "No terminal windows on this workspace."])
      return
    }
    console.log("td-paint: overlay up — " + tileModel.count + " tile(s), " + root.variants.length + " variants")
    root.opened = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  ListModel { id: tileModel }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🎨"
    tooltipText: "Paint terminals — left: pick per tile · middle: TD panes everywhere · right: done painting"

    // Left paints HERE (the workspace you are looking at), middle raises
    // Terminal Delight's pane picker on every workspace, right lowers every
    // brush — three buttons, three meanings (TASTE rule 9).
    onPressed: function (b) {
      if (b === Qt.LeftButton) {
        root.paintToggle()
      } else if (b === Qt.MiddleButton) {
        Quickshell.execDetached(["terminal-delight", "ctl", "paint", "toggle", "--all"])
      } else if (b === Qt.RightButton) {
        root.paintDismiss(false)
      }
    }
  }

  // The keyboard-first path (TASTE rule 7): `omarchy-shell
  // brownfamilysports.td-palette toggle` does what a left click does — same
  // functions the button calls, no IPC round trip.
  IpcHandler {
    target: "brownfamilysports.td-palette"

    function toggle(): void { root.paintToggle() }
    function open(): void { root.paintOpen() }
    function close(): void { root.paintDismiss(false) }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "td-palette-paint"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // the room lights dim; the tiles under the cards stay legible
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.paintDismiss(false)
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.paintDismiss(false)
          event.accepted = true
        }
      }
    }

    Repeater {
      model: tileModel
      delegate: Item {
        required property var model
        // the inner variant Repeater runs its delegates in required-property
        // mode, where the outer `model` context is out of reach — alias what
        // the cards need onto the tile root instead
        property string tileAddress: model.address
        x: model.tx
        y: model.ty
        width: model.tw
        height: model.th

        Rectangle {
          id: card
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(620))
          height: content.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: Math.max(1, Style.space(1))

          // swallow the click so the scrim's dismiss never fires under a card
          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: content
            anchors.centerIn: parent
            width: card.width - Style.spacing.panelPadding * 2
            spacing: Style.spacing.md

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: model.td ? "TERMINAL DELIGHT" : "PAINT THIS TERMINAL"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: Style.space(2)
            }

            // Terminal Delight: one handoff card — its own picker is per-pane
            // and persistent, strictly better than a window-level tint.
            Rectangle {
              visible: model.td
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(220)
              height: Style.space(52)
              radius: Style.cornerRadius
              color: "transparent"
              border.color: Color.menu.border
              border.width: 1
              Text {
                anchors.centerIn: parent
                text: "🎨  open the pane picker"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  Quickshell.execDetached(["terminal-delight", "ctl", "paint", "on", "--pid", String(model.pid)])
                  root.paintDismiss(true)
                }
              }
            }

            Flow {
              visible: !model.td
              width: parent.width
              spacing: Style.spacing.sm

              // the ⟲ card first: back to whatever the desktop theme says
              Rectangle {
                width: Style.space(64)
                height: Style.space(64)
                radius: Style.cornerRadius
                color: "transparent"
                border.color: Color.menu.border
                border.width: 1
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "⟲"
                    color: Color.menu.text
                    font.pixelSize: Style.font.heading
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DESKTOP"
                    color: Color.menu.text
                    opacity: 0.65
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: Quickshell.execDetached(["td-tint", "--window", tileAddress, "--clear"])
                }
              }

              Repeater {
                model: root.variants
                delegate: Rectangle {
                  required property var modelData
                  width: Style.space(64)
                  height: Style.space(64)
                  radius: Style.cornerRadius
                  color: "transparent"
                  // the variant's own two colours ARE the data being chosen —
                  // this border is content, not chrome
                  border.color: modelData.accent
                  border.width: 1
                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.glyph
                      font.pixelSize: Style.font.heading
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.key.toUpperCase()
                      color: Color.menu.text
                      opacity: 0.75
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Style.space(34)
                      height: Style.space(3)
                      radius: Style.space(1)
                      color: modelData.partner
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: Quickshell.execDetached(["td-tint", "--window", tileAddress, modelData.key])
                  }
                }
              }
            }

            // SATURATE — the overflowing paint can: crank this tile's text
            // colour to the Terminal Delight look, click again to pour it
            // back. Stateless chip by design; td-tint's record carries the
            // truth and --sync re-applies it.
            Rectangle {
              visible: !model.td
              anchors.horizontalCenter: parent.horizontalCenter
              width: satLabel.implicitWidth + Style.space(24)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: "transparent"
              border.color: Color.menu.border
              border.width: 1
              Text {
                id: satLabel
                anchors.centerIn: parent
                text: "🫗  SATURATE"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["td-tint", "--window", tileAddress, "--saturate", "toggle"])
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "esc · done"
              color: Color.menu.text
              opacity: 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
