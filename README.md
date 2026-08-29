# Terminal Paint

A painter's palette in the Omarchy bar. Click it and **every terminal tile on
your active workspace** grows a picker card — 🦇 ☢ 🤡 🌊 🔥 and the rest of
the [Terminal Delight](https://github.com/parker-brown-family/terminal-delight)
variant family. Click a glyph on a card and *that tile* takes that identity:

- **foot / Alacritty / kitty / Ghostty / WezTerm** — the card floats over the
  window; a pick runs `td-tint --window <address> <variant>`, which writes the
  variant's OSC palette down that terminal's own tty and puts the matching
  gradient on its window border. Runtime-only, dies with the window; the ⟲
  DESKTOP card hands the tile back to the desktop theme.
- **Terminal Delight** — its story is better than a window tint (per-pane,
  persistent, CRT-identity-preserving), so its card is a single handoff that
  raises TD's own in-app pane picker over its control socket and gets out of
  the way.

Esc, or a click on the dimmed background, or a second click on the palette:
brushes away everywhere.

## What this plugin runs, reads, and sends

Plugins are unsandboxed, so here is the whole footprint:

- **Runs, on summon:** one `bash -c` snapshot — `td-tint --json` (the installed
  variant list) plus `hyprctl -j activeworkspace / clients / monitors` (where
  the terminal tiles are). **Runs, on a card click:** `td-tint --window …` or
  `terminal-delight ctl paint …`. **Runs, on an empty workspace:** one
  transient `notify-send` saying so. Nothing resident, nothing polled; the only
  timer is a one-shot 120 ms collector wait after the snapshot.
- **Reads:** nothing beyond those command outputs. **Writes:** nothing.
  **Network:** none, ever.
- While the overlay is up it holds exclusive keyboard focus (that is what
  makes Esc work); it releases everything on dismiss.

## Requirements

- The Terminal Delight variant set installed
  ([omarchy-terminal-delight-theme](https://github.com/parker-brown-family/omarchy-terminal-delight-theme)
  → `./install-variants.sh`), which also puts `td-tint` on `PATH`.
- For Terminal Delight windows: a `terminal-delight` build with the control
  socket (`feat/td-paint-mode` or later). Terminals started from older builds
  can't be reached — reopen them.

## Buttons

| Button | Means |
|---|---|
| Left | the picker, over every terminal tile on **this** workspace |
| Middle | Terminal Delight's pane picker on **every** workspace |
| Right | done painting, everywhere |

## Keyboard

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER SHIFT", "P", function()
  hl.dsp.exec_cmd("omarchy-shell -q shell toggle brownfamilysports.td-palette")
end)
```

## Install

```bash
omarchy plugin add https://github.com/parker-brown-family/omarchy-td-palette.git --enable
```

(Until graduation this plugin lives in the lab's incubator and is dev-linked;
the URL above goes live when it ships.)

MIT.
