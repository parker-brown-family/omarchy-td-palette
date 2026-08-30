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
// overlay it raises: a "PAINT THIS TERMINAL" picker floated over every
// terminal TILE on the active workspace.
//
// The colours are OMARCHY'S OWN — every theme installed on this box, aimed at
// ONE tile instead of the whole desktop. It is the same colors.toml, down the
// same tty, through the same OSC that a theme switch would use; the only
// difference is how far it reaches.
//
// There is no second list and no source switch. Terminal Delight ships eleven
// hand-made palettes and they are good, but a picker that offers our set
// beside the desktop's is a picker asking you to hold an opinion about whose
// colours are better before you can paint a terminal. Omarchy's set is larger,
// maintained by people who do this, and already the vocabulary you chose your
// desktop from — and Terminal Delight is IN it, as one theme, so nothing is
// out of reach. `td-tint cherry` still wears a palette from a prompt.
//
// The list is read fresh on every summon — `td-tint --state` globs the theme
// directories at the moment you press the key, so a theme installed a minute
// ago is on the card grid, and one uninstalled a minute ago is not. F5 re-reads
// without closing, for when the install happened in the window behind this one.
//
// Each tile also has a TUBE: the barrel warp and glass glare that
// `shaders/surface.frag` draws for any window with a rounding radius. That
// makes rounding the switch, and it is the only live one — Hyprland reads
// window shaders once at startup. So CRT is per tile, and CRT ALL is the
// workspace, exactly as SATURATE is.
//
// The practical dividend: every lowercase letter belongs to a theme NAME. A
// verb bound to one steals it — `o` was the source switch and `osaka-jade`
// wanted it, `s` was saturate and `solitude` wanted it, and `d` was safe only
// until someone installs `dracula`. So the rule here is absolute: letters
// name themes, everything else is a verb.
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

  // What a summon snapshot found: the installed themes, and the terminal tiles
  // (monitor-local rects) of the active workspace.
  property var cards: []

  // The theme the desktop is wearing at the moment of the snapshot. The card
  // that matches is marked, so the grid says what you are deviating FROM
  // rather than making you remember it.
  property string desktopTheme: ""

  // Whether the per-window warp is installed at all. A CRT switch on a box
  // without `shaders/surface.frag` would be a control that does nothing, so
  // the overlay says why instead of drawing one.
  property bool crtAvailable: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // One summon, one document. The run token is what makes delivery
  // idempotent: whichever of the two signals below arrives first wins, and
  // the other becomes a no-op instead of a second overlay.
  property int snapRun: 0
  property int snapTaken: -1

  function paintOpen() {
    console.log("td-paint: open — snapshotting")
    root.snapRun++
    snapshot.running = false
    snapshot.running = true
  }

  function consumeOnce(raw) {
    if (root.snapTaken === root.snapRun) return
    root.snapTaken = root.snapRun
    snapWatchdog.stop()
    root.consume(raw)
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

  // Optimistic card state: a click fires the command AND marks the model, so
  // the open overlay reflects the pick immediately; reopening re-reads the
  // records, which remain the truth. The source is marked with the key: a
  // tile wearing a Terminal Delight palette from the command line has a pick
  // this picker cannot show, and it must light no card rather than the card
  // of whatever theme happens to share its name.
  function markPicked(i, key, src) {
    tileModel.setProperty(i, "picked", key)
    tileModel.setProperty(i, "src", src === undefined ? "omarchy" : src)
  }
  function markSat(i, on) { tileModel.setProperty(i, "sat", on); root.refreshAllSat() }
  function markCrt(i, on) { tileModel.setProperty(i, "crt", on); root.refreshAllCrt() }

  // The workspace-wide crank state the global toggle shows: ON only when
  // every paintable tile is cranked. ListModel edits don't re-run bindings,
  // so markSat/consume refresh it by hand.
  property bool allSat: false
  function refreshAllSat() {
    var anyOsc = false, all = true
    for (var i = 0; i < tileModel.count; i++) {
      var t = tileModel.get(i)
      if (t.td) continue
      anyOsc = true
      if (!t.sat) all = false
    }
    root.allSat = anyOsc && all
  }

  // Same rule for the tube: ON only when every paintable tile has it.
  property bool allCrt: false
  function refreshAllCrt() {
    var any = false, all = true
    for (var i = 0; i < tileModel.count; i++) {
      var t = tileModel.get(i)
      if (t.td) continue
      any = true
      if (!t.crt) all = false
    }
    root.allCrt = any && all
  }

  // One switch, everywhere: label + a chunky track that SAYS which state it
  // is in. The knob slides, the track fills, and the word ON/OFF sits in the
  // empty half — state you can read from across the room, mouse-clickable.
  component SatToggle: Item {
    id: st
    property string label: "SATURATE"
    property bool on: false
    signal flipped()
    implicitWidth: stRow.implicitWidth
    implicitHeight: Style.space(30)

    Row {
      id: stRow
      spacing: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: st.label
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.space(1)
      }

      Rectangle {
        id: stTrack
        width: Style.space(52)
        height: Style.space(24)
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: st.on ? Color.menu.selectedBackground : "transparent"
        border.color: st.on ? Color.menu.selectedBackground : Color.menu.border
        border.width: 1
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: st.on ? Style.space(7) : stTrack.width - implicitWidth - Style.space(7)
          text: st.on ? "ON" : "OFF"
          color: st.on ? Color.menu.selectedText : Color.menu.text
          opacity: st.on ? 1 : 0.6
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption - 2
          font.bold: true
        }

        Rectangle {
          width: stTrack.height - Style.space(6)
          height: width
          radius: width / 2
          y: Style.space(3)
          x: st.on ? stTrack.width - width - Style.space(3) : Style.space(3)
          color: st.on ? Color.menu.selectedText : Color.menu.text
          Behavior on x { NumberAnimation { duration: 100 } }
        }
      }
    }

    MouseArea { anchors.fill: parent; onClicked: st.flipped() }
  }

  // ---- keyboard-first: everything a click can do, off the home row. One
  // selected tile (opens on the window you were just focused in); bare
  // arrows walk reading order; a variant's FIRST LETTER paints the selected
  // tile (the set was renamed so every letter is unique: a b c e g n p r t
  // v w). Lowercase acts on the tile, uppercase on the workspace.
  property int sel: 0
  function selStep(d) {
    var n = tileModel.count
    if (n > 0) root.sel = ((root.sel + d) % n + n) % n
  }

  // The argv that paints ONE window. `--theme` carries its own name rather
  // than leaving it positional, because td-tint knows two namespaces and a
  // word in both must never be resolved by guesswork.
  function paintArgs(addr, key) {
    return ["td-tint", "--window", addr, "--theme", key]
  }

  function applyCard(i, c) {
    var t = tileModel.get(i)
    if (!t || t.td) return
    Quickshell.execDetached(root.paintArgs(t.address, c.key))
    root.markPicked(i, c.key)  // SATURATE rides along: td-tint keeps it
  }

  // A letter jumps to the first theme whose NAME starts with it, and pressing
  // it again walks to the next one that does. Three themes start with `c`
  // here and three with `r`, so a letter cannot own one card; cycling is the
  // only thing that works, and it costs nothing, because painting is instant
  // and Backspace puts it back.
  function applyLetter(ch) {
    var t = tileModel.get(root.sel)
    if (!t || t.td) return
    var cards = root.cards
    if (!cards.length) return
    var start = 0
    for (var j = 0; j < cards.length; j++) {
      if (cards[j].key === t.picked && t.src === "omarchy") { start = j + 1; break }
    }
    for (var i = 0; i < cards.length; i++) {
      var c = cards[(start + i) % cards.length]
      if (c.label.charAt(0).toLowerCase() === ch) {
        root.applyCard(root.sel, c)
        return
      }
    }
  }
  function clearSel() {
    var t = tileModel.get(root.sel)
    if (!t || t.td) return
    Quickshell.execDetached(["td-tint", "--window", t.address, "--clear"])
    root.markPicked(root.sel, "-", "")
    root.markSat(root.sel, false)
    root.markCrt(root.sel, root.crtAvailable)
  }
  function satSel() {
    var t = tileModel.get(root.sel)
    if (!t || t.td) return
    Quickshell.execDetached(["td-tint", "--window", t.address, "--saturate", "toggle"])
    root.markSat(root.sel, !t.sat)
  }
  function tdSel() {
    var t = tileModel.get(root.sel)
    if (!t || !t.td) return
    Quickshell.execDetached(["terminal-delight", "ctl", "paint", "on", "--pid", String(t.pid)])
    root.paintDismiss(true)
  }
  function crtSel() {
    var t = tileModel.get(root.sel)
    if (!t || t.td || !root.crtAvailable) return
    Quickshell.execDetached(["td-tint", "--window", t.address, "--crt", t.crt ? "off" : "on"])
    root.markCrt(root.sel, !t.crt)
  }
  function crtAll(on) {
    if (!root.crtAvailable) return
    for (var i = 0; i < tileModel.count; i++) {
      var t = tileModel.get(i)
      if (t.td) continue
      Quickshell.execDetached(["td-tint", "--window", t.address, "--crt", on ? "on" : "off"])
      root.markCrt(i, on)
    }
  }
  function crtAllToggle() { root.crtAll(!root.allCrt) }

  function satAll(on) {
    for (var i = 0; i < tileModel.count; i++) {
      var t = tileModel.get(i)
      if (t.td) continue
      Quickshell.execDetached(["td-tint", "--window", t.address, "--saturate", on ? "on" : "off"])
      root.markSat(i, on)
    }
  }
  // The global toggle mirrors the switch it drives: everything cranked ->
  // pour it all back, anything dry -> crank it all.
  function satAllToggle() { root.satAll(!root.allSat) }
  function resetAll() {
    for (var i = 0; i < tileModel.count; i++) {
      var t = tileModel.get(i)
      if (t.td) continue
      Quickshell.execDetached(["td-tint", "--window", t.address, "--clear"])
      root.markPicked(i, "-", "")
      root.markSat(i, false)
      // --clear hands the tube back too, so the model has to say so or the
      // rail's CRT ALL keeps claiming a state the tiles no longer hold.
      root.markCrt(i, root.crtAvailable)
    }
  }

  // One process, one document: `td-tint --state` is the paint oracle. The
  // ENGINE owns window filtering, record parsing, monitor offsets and the
  // focused window — all tested in its suite — and this view only renders.
  // Fetched at summon time; no polling — the picker sees the workspace as it
  // was when you rang it, which is also the workspace you were looking at.
  Process {
    id: snapshot
    command: ["td-tint", "--state"]
    // Gated on the collector draining, not on a clock. `waitForEnd` holds the
    // buffer until stdout actually closes and `streamFinished` says when. The
    // old fixed 120 ms wait was the only gate, and it was wrong in both
    // directions — it truncates the document on a slow pipe and idles on a
    // fast one, and neither failure announces itself.
    stdout: StdioCollector {
      id: snapText
      waitForEnd: true
      onStreamFinished: root.consumeOnce(snapText.text)
    }
    // Exit is deliberately NOT the read signal: with waitForEnd the buffer can
    // still be filling here, which is the truncation the timer used to cause.
    // It only arms a watchdog, so a process that ends without the stream
    // closing cleanly still surfaces something rather than hanging the summon.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, exitStatus) {
      // …unless the document already landed. Exit normally arrives AFTER the
      // stream closes, and re-arming here fired the watchdog two seconds into
      // every successful summon: a no-op guarded by the run token, but a log
      // line that read like a failure on the happy path.
      if (root.snapTaken === root.snapRun) return
      snapWatchdog.restart()
    }
    // qmllint enable signal-handler-parameters
  }

  // Liveness only, never the happy path — an order of magnitude past the old
  // wait, and cancelled the moment the drain signal lands.
  Timer {
    id: snapWatchdog
    interval: 2000
    onTriggered: {
      console.log("td-paint: stream never closed — reading the watchdog buffer")
      root.consumeOnce(snapText.text)
    }
  }

  // The trust boundary, and the reason the rest of this file can be read as
  // if the oracle were honest. The theme list `td-tint --state` reports is not
  // ours in any sense: the names are DIRECTORY NAMES from
  // ~/.config/omarchy/themes and Omarchy's own share — anyone's, including a
  // theme cloned from a stranger's repo an hour ago — and the colours are
  // whatever that theme's colors.toml says. Every label drawn below, every
  // card colour, and every argv word handed to `td-tint` is built from that
  // list, so it is normalised HERE, once, and a record that does not fit the
  // shape is dropped rather than repaired.
  //
  //   key      the identity AND the argv word. Lower alphanumeric with inner
  //            dashes, never leading `-`: it can carry no markup, and it can
  //            never be read by td-tint as a flag.
  //   label    what a human reads, and the letter the keyboard matches.
  //            Display only — never argv — so it may carry spaces and case,
  //            but control characters are cut and the length is capped.
  //   colours  #rgb / #rrggbb / #aarrggbb only — anything else lands in a
  //            string→color coercion whose failure modes are not ours.
  readonly property var keyRe: /^[a-z0-9][a-z0-9-]{0,31}$/
  readonly property var hexRe: /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
  // Hyprland window handles, the argv word behind `--window` and (inside
  // td-tint) a filename under its run dir. Anchored so no separator, no
  // traversal and no leading dash can reach either.
  readonly property var addrRe: /^0x[0-9a-fA-F]{1,16}$/

  // A colour we would otherwise coerce from an unchecked string, with the
  // fallback stated rather than left to Qt: an invalid colour string reads as
  // black, and a black accent on a black card is an invisible card.
  function hexOr(v, fallback) {
    return (typeof v === "string" && root.hexRe.test(v)) ? v : fallback
  }

  function sanitizeCards(list, what) {
    if (!Array.isArray(list)) return []
    var out = []
    // 96 rather than 64: a well-stocked box carries more themes than there
    // are palettes, and a picker that silently stops at some of them is worse
    // than one that draws a long grid.
    for (var i = 0; i < list.length && out.length < 96; i++) {
      var v = list[i]
      if (!v || typeof v.key !== "string" || !root.keyRe.test(v.key)) continue
      if (typeof v.accent !== "string" || !root.hexRe.test(v.accent)) continue
      if (typeof v.partner !== "string" || !root.hexRe.test(v.partner)) continue
      var label = typeof v.label === "string" && v.label.length ? v.label : v.key
      label = label.replace(/[\x00-\x1f\x7f]/g, "").slice(0, 28)
      if (!label.length) continue
      out.push({
        key: v.key,
        label: label,
        accent: v.accent,
        partner: v.partner,
        // taste-ok (rule 3): not a colour this plugin chose to draw — it is
        // the floor under a card whose OWN background failed validation. A
        // theme swatch has to be drawn on something, and a themed surface
        // here would misreport the theme being previewed as darker or
        // lighter than it is.
        bg: root.hexOr(v.bg, "#000000"),  // taste-ok: the floor, not a choice
        fg: root.hexOr(v.fg, v.accent)
      })
    }
    var dropped = list.length - out.length
    if (dropped > 0)
      console.log("td-paint: dropped " + dropped + " malformed " + what + " record(s)")
    return out
  }

  // A window we will not aim a command at is a window we will not draw a card
  // over — the guard is one predicate so the two can never disagree.
  function validAddr(a) { return typeof a === "string" && root.addrRe.test(a) }

  // The document is a few kilobytes for a busy workspace. Past this ceiling it
  // is not a state document, and it is dropped instead of parsed.
  readonly property int stateLimit: 262144

  function consume(raw) {
    var st
    if (typeof raw !== "string" || raw.length === 0) return
    if (raw.length > root.stateLimit) {
      console.log("td-paint: state of " + raw.length + " bytes exceeds the "
                  + root.stateLimit + "-byte ceiling — dropped unparsed")
      return
    }
    try {
      st = JSON.parse(raw)
    } catch (e) {
      console.log("td-paint: state parse failed: " + e)
      return
    }
    if (!st || !st.tiles || !st.monitor) return
    console.log("td-paint: state — " + st.tiles.length + " tile(s), "
                + (st.themes ? st.themes.length : 0) + " themes, crt="
                + (st.crt && st.crt.available ? "available" : "unavailable"))

    // where the keyboard opens: on the tile you were just working in
    var focusAddr = st.focused || ""

    var tiles = []
    var oscCount = 0
    var anyTd = false
    st.tiles.forEach(function (t) {
      if (!t.on_active_workspace) return
      if (!root.validAddr(t.address)) return
      if (t.terminal_delight) anyTd = true
      else oscCount++
      tiles.push({
        address: t.address,
        pid: t.pid,
        td: t.terminal_delight,
        tx: t.at[0] - st.monitor.x,
        ty: t.at[1] - st.monitor.y,
        tw: t.size[0],
        th: t.size[1],
        picked: t.variant || "",
        src: t.source === "omarchy" ? "omarchy" : "",
        crt: t.crt === true,
        sat: t.saturated === true
      })
    })
    // reading order — the order the bare arrows walk
    tiles.sort(function (a, b) { return (a.ty - b.ty) || (a.tx - b.tx) })
    tileModel.clear()
    root.sel = 0
    for (var t = 0; t < tiles.length; t++) {
      tileModel.append(tiles[t])
      if (tiles[t].address === focusAddr) root.sel = t
    }
    root.refreshAllSat()
    root.refreshAllCrt()
    root.cards = root.sanitizeCards(st.themes, "theme")
    root.crtAvailable = !!(st.crt && st.crt.available === true)
    // The desktop's theme is a key from the same list, so it gets the same
    // regex — a name that could not be a card cannot be a marker either.
    root.desktopTheme = (typeof st.desktop_theme === "string"
                         && root.keyRe.test(st.desktop_theme)) ? st.desktop_theme : ""

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
    // No colours is a different failure from no terminals, and saying so is
    // the difference between "my themes are missing" and a grid of empty
    // cards the user is left to interpret.
    if (root.cards.length === 0) {
      Quickshell.execDetached(["notify-send", "-a", "Terminal Paint", "-e",
        "No themes to paint with",
        "td-tint reported no installed Omarchy themes. Is td-tint current?"])
      return
    }
    console.log("td-paint: overlay up — " + tileModel.count + " tile(s), "
                + root.cards.length + " theme card(s)")
    root.opened = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  ListModel { id: tileModel }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🎨"
    tooltipText: "Paint terminals — left: give each tile its own Omarchy theme · "
               + "middle: TD panes everywhere · right: done painting"

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
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
          root.selStep(-1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
            || event.key === Qt.Key_Tab) {
          root.selStep(1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.tdSel(); event.accepted = true; return
        }
        // Space saturates the selected tile, Backspace hands it back to the
        // desktop. Both used to be letters — `s` and `d` — and both were
        // wrong for the same reason: a lowercase letter belongs to a theme
        // NAME, and `s` was already stealing `solitude`. Verbs live on keys
        // that can never be a name, and the two workspace-wide verbs stay on
        // SHIFTED letters, which the name-matching path never sees.
        // Shift makes it the OTHER switch on the same tile. Both are
        // per-tile state, both are a toggle, and pairing them on one key is
        // what keeps CRT off the alphabet.
        if (event.key === Qt.Key_Space) {
          if (event.modifiers & Qt.ShiftModifier) root.crtSel()
          else root.satSel()
          event.accepted = true; return
        }
        // The list is read fresh on every summon; F5 re-reads WITHOUT closing,
        // for the theme you installed in the window behind this one.
        if (event.key === Qt.Key_F5) { root.paintOpen(); event.accepted = true; return }
        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
          root.clearSel(); event.accepted = true; return
        }
        var ch = event.text
        if (ch === "S") { root.satAllToggle(); event.accepted = true; return }
        if (ch === "C") { root.crtAllToggle(); event.accepted = true; return }
        if (ch === "R") { root.resetAll(); event.accepted = true; return }
        if (ch >= "a" && ch <= "z") { root.applyLetter(ch); event.accepted = true }
      }
    }

    Repeater {
      model: tileModel
      delegate: Item {
        id: tileRoot
        required property var model
        required property int index
        // the inner variant Repeater runs its delegates in required-property
        // mode, where the outer `model` context is out of reach — alias what
        // the cards need onto the tile root instead (lexical scoping still
        // reaches these; only the model context is disabled in there)
        property string tileAddress: model.address
        property int tileIndex: index
        property string pickedNow: model.picked
        property string pickedSrc: model.src
        property bool satNow: model.sat
        property bool crtNow: model.crt
        readonly property bool onDesktop: pickedNow === "" || pickedNow === "-"
        readonly property bool tileSel: index === root.sel
        x: model.tx
        y: model.ty
        width: model.tw
        height: model.th

        // the spotlight: unselected tiles wear TWO extra coats of the theme's
        // own scrim (three with the base), the selected one only the base —
        // the lit tile reads from across the room
        Rectangle {
          anchors.fill: parent
          color: Color.menu.scrim
          opacity: tileSel ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Rectangle {
          anchors.fill: parent
          color: Color.menu.scrim
          opacity: tileSel ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // and the selected tile is FRAMED — a bright band around the whole
        // window, not just its card
        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(2)
          color: "transparent"
          radius: Style.cornerRadius
          border.color: Color.menu.text
          border.width: Style.space(3)
          opacity: tileSel ? 0.9 : 0
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Rectangle {
          id: card
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(620))
          height: content.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: Color.menu.background
          // the SELECTED painter wears the bright ring; unselected cards sit
          // faded behind a quiet one (selectedBackground made this read
          // exactly backward — it vanishes into the card fill)
          border.color: tileSel ? Color.menu.text : Color.menu.border
          border.width: tileSel ? 3 : Math.max(1, Style.space(1))
          opacity: tileSel ? 1 : 0.3
          scale: tileSel ? 1 : 0.94
          Behavior on opacity { NumberAnimation { duration: 120 } }
          Behavior on scale { NumberAnimation { duration: 120 } }

          // swallow the click so the scrim's dismiss never fires under a card
          // — and let a click bring the keyboard here (mouse and arrows agree)
          MouseArea { anchors.fill: parent; onClicked: root.sel = tileIndex }

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

            // The grid grows with the list — a well-stocked box carries thirty
            // themes where there are eleven palettes — but never past the
            // terminal it is drawn in. Past that it scrolls, which beats a
            // card spilling out of its own tile and over its neighbours.
            Flickable {
              id: grid
              visible: !model.td
              width: parent.width
              height: Math.min(gridFlow.implicitHeight,
                               Math.max(Style.space(160), tileRoot.height - Style.space(200)))
              contentHeight: gridFlow.implicitHeight
              contentWidth: width
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height

              Flow {
                id: gridFlow
                width: grid.width
                spacing: Style.spacing.sm

                // the ⟲ card first: back to whatever the desktop theme says.
                // Lit while the tile follows the desktop (no recorded variant).
                Rectangle {
                  width: Style.space(78)
                  height: Style.space(78)
                  radius: Style.cornerRadius
                  color: onDesktop ? Color.menu.selectedBackground : "transparent"
                  border.color: Color.menu.border
                  border.width: onDesktop ? 2 : 1
                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "⟲"
                      color: onDesktop ? Color.menu.selectedText : Color.menu.text
                      font.pixelSize: Style.font.heading
                    }
                    // The key IS the label. Same two-Text mechanism as the
                    // theme cards below — the ⟲ card's name is ours and could
                    // safely be rich text, but a picker where one card is drawn
                    // by a different code path is a picker where one card drifts.
                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      Text {
                        id: dInitial
                        textFormat: Text.PlainText
                        text: "D"
                        color: onDesktop ? Color.menu.selectedText : Color.menu.text
                        opacity: 1
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption + 7
                        font.weight: Font.Black
                        font.underline: true
                      }
                      Text {
                        anchors.baseline: dInitial.baseline
                        textFormat: Text.PlainText
                        text: "ESKTOP"
                        color: onDesktop ? Color.menu.selectedText : Color.menu.text
                        opacity: onDesktop ? 0.8 : 0.55
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      Quickshell.execDetached(["td-tint", "--window", tileAddress, "--clear"])
                      root.markPicked(tileIndex, "-", "")
                    }
                  }
                }

                Repeater {
                  model: root.cards
                  delegate: Rectangle {
                    id: cardTile
                    required property var modelData
                    // string → color coercion happens on the typed property,
                    // which is what makes Qt.alpha below safe to call
                    readonly property color acc: modelData.accent
                    // A tile wearing a Terminal Delight palette from a prompt has a pick
                    // this picker cannot show — it lights nothing, rather than the card of
                    // whatever theme happens to share its name.
                    readonly property bool lit: modelData.key === pickedNow
                                                && pickedSrc === "omarchy"
                    // The theme the desktop itself is wearing. Marked, not
                    // hidden: it is a perfectly good thing to paint a tile
                    // with, and knowing which one it is turns the grid into a
                    // set of deviations from something rather than a wall.
                    readonly property bool isDesktop: modelData.key === root.desktopTheme
                    width: Style.space(78)
                    height: Style.space(78)
                    radius: Style.cornerRadius
                    // the entry's own two colours ARE the data being chosen —
                    // this border is content, not chrome; the current pick gets
                    // a thicker ring and a wash of its own accent
                    color: lit ? Qt.alpha(acc, 0.16) : "transparent"
                    border.color: acc
                    border.width: lit ? 2 : 1
                    Column {
                      anchors.centerIn: parent
                      spacing: Style.space(2)

                      // A theme gets no glyph and should not be given one: what tells
                      // Osaka Jade from Tokyo Night IS the colour. So the face is a small
                      // terminal drawn in the theme's own background, accent and
                      // foreground — the thing the card actually does, rather than a face
                      // invented for it.
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(36)
                        height: Style.space(26)
                        radius: Style.space(4)
                        color: modelData.bg
                        border.color: cardTile.isDesktop ? Color.menu.text
                                                         : Qt.alpha(cardTile.acc, 0.55)
                        border.width: cardTile.isDesktop ? 2 : 1
                        Column {
                          anchors.centerIn: parent
                          spacing: Style.space(3)
                          Rectangle {
                            width: Style.space(19); height: Style.space(3)
                            radius: Style.space(2); color: cardTile.acc
                          }
                          Rectangle {
                            width: Style.space(13); height: Style.space(3)
                            radius: Style.space(2); color: modelData.fg
                          }
                          Rectangle {
                            width: Style.space(16); height: Style.space(3)
                            radius: Style.space(2); color: modelData.partner
                          }
                        }
                      }
                      // Press the FIRST LETTER to paint, so the first letter is
                      // drawn the way it is pressed: seven points up, Black
                      // weight, underlined, at full strength, and inked in the
                      // variant's OWN accent so the key also previews the colour
                      // it applies. The rest of the name falls back to caption
                      // size at 0.6 — the contrast is the point, and a name is
                      // only there to confirm what the glyph already said.
                      //
                      // Two plain Text items rather than one rich one: the label
                      // is a name written in another repository, and a draw path
                      // that never assembles markup cannot be made to render any.
                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                          id: initial
                          textFormat: Text.PlainText
                          text: modelData.label.charAt(0).toUpperCase()
                          color: acc
                          opacity: 1
                          font.family: Style.font.menuFamily
                          font.pixelSize: Style.font.caption + 7
                          font.weight: Font.Black
                          font.underline: true
                        }
                        Text {
                          anchors.baseline: initial.baseline
                          textFormat: Text.PlainText
                          text: modelData.label.slice(1).toUpperCase()
                          color: Color.menu.text
                          opacity: lit ? 0.8 : 0.6
                          font.family: Style.font.menuFamily
                          font.pixelSize: Style.font.caption
                          // Theme names run long where palette keys never did
                          // (`catppuccin-latte` is sixteen characters). Elide
                          // inside the card rather than let one name set the
                          // width of every card in the grid.
                          width: Math.max(0, cardTile.width - initial.width - Style.space(8))
                          elide: Text.ElideRight
                        }
                      }
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(38)
                        height: Style.space(3)
                        radius: Style.space(1)
                        color: modelData.partner
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        // SATURATE rides along — td-tint carries it across coats
                        root.applyCard(tileIndex, modelData)
                        root.sel = tileIndex
                      }
                    }
                  }
                }
              }
            }

            // SATURATE — crank this tile's text to the Terminal Delight look.
            // One switch that shows its state; td-tint's record carries the
            // truth and --sync re-applies it.
            // The two things a tile can be beyond its colour: how hard the
            // text burns, and whether it sits behind curved glass. Side by
            // side, because they are the same kind of choice about the same
            // tile — and the CRT switch is simply absent on a box without the
            // per-window warp, rather than present and inert.
            Row {
              visible: !model.td
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.md

              SatToggle {
                anchors.verticalCenter: parent.verticalCenter
                label: "SATURATE"
                on: satNow
                onFlipped: {
                  Quickshell.execDetached(["td-tint", "--window", tileAddress, "--saturate", "toggle"])
                  root.markSat(tileIndex, !satNow)
                }
              }

              SatToggle {
                visible: root.crtAvailable
                anchors.verticalCenter: parent.verticalCenter
                label: "CRT"
                on: crtNow
                onFlipped: {
                  Quickshell.execDetached(["td-tint", "--window", tileAddress,
                                           "--crt", crtNow ? "off" : "on"])
                  root.markCrt(tileIndex, !crtNow)
                }
              }
            }

          }
        }
      }
    }

    // ---- the global rail, top and centre: one place to act on EVERY tile
    // at once, and the legend that makes the overlay playable eyes-closed.
    Rectangle {
      id: globalPanel
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(36)
      width: globalCol.implicitWidth + Style.spacing.panelPadding * 2
      height: globalCol.implicitHeight + Style.spacing.panelPadding * 2
      radius: Style.cornerRadius
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: Math.max(1, Style.space(1))

      // swallow clicks so the scrim's dismiss never fires under the rail
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: globalCol
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "TERMINAL PAINT"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: Style.space(2)
        }

        // Where the cards came from, said out loud. The count is read at
        // summon, so it is also the proof that the list is this machine's
        // right now rather than something baked in — and naming the desktop's
        // own theme is what makes "back to the desktop" a place, not an idea.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.cards.length + " OMARCHY THEMES ON THIS MACHINE"
              + (root.desktopTheme ? "  ·  DESKTOP WEARS " + root.desktopTheme.toUpperCase() : "")
              + "  ·  F5 RE-READS"
          color: Color.menu.text
          opacity: 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.space(1)
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.md

          SatToggle {
            anchors.verticalCenter: parent.verticalCenter
            label: "SATURATE ALL"
            on: root.allSat
            onFlipped: root.satAll(!root.allSat)
          }

          SatToggle {
            visible: root.crtAvailable
            anchors.verticalCenter: parent.verticalCenter
            label: "CRT ALL"
            on: root.allCrt
            onFlipped: root.crtAll(!root.allCrt)
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: resetAllLabel.implicitWidth + Style.space(24)
            height: Style.space(30)
            radius: Style.cornerRadius
            color: "transparent"
            border.color: Color.menu.border
            border.width: 1
            Text {
              id: resetAllLabel
              anchors.centerIn: parent
              text: "⟲  RESET DEFAULTS"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; onClicked: root.resetAll() }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "←→ select · letter picks a theme (again for the next match) · "
              + "␣ saturate" + (root.crtAvailable ? " · ⇧␣ CRT" : "") + " · ⌫ desktop · "
              + "S" + (root.crtAvailable ? "/C" : "") + " all · R reset · ⏎ TD picker · esc done"
          color: Color.menu.text
          opacity: 0.5
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
