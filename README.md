# Terminal Paint

A painter's palette in the Omarchy bar. Click it and every
[Terminal Delight](https://github.com/parker-brown-family/terminal-delight)
pane on your active workspace grows a glyph overlay — 🦇 ☢ 🤡 🌊 🔥 and the
rest of the colour-set family. Click a glyph on a pane and *that pane* takes
that palette; its CRT identity (scanlines, curvature, grade) stays put. Esc,
or a second click on the palette, and the brushes go away. The recolour
persists across restarts — it lands in the terminal's own per-pane state.

## What this plugin runs, reads, and sends

Plugins are unsandboxed, so here is the whole footprint:

- **Runs:** `terminal-delight ctl paint <on|off|toggle> [--all]` — one
  short-lived process per click, nothing resident, no timers except two
  one-shots after a failed call (the 1.6 s face reset and a 120 ms collector
  wait). On failure it also runs `notify-send` once, carrying the ctl client's
  own diagnosis (e.g. "no control socket — reopen this terminal") as a
  transient notification.
- **Reads:** nothing. **Writes:** nothing. **Network:** none, ever.
- The overlay itself is rendered by terminal-delight inside its own windows
  (Wayland does not let one client paint into another). The terminal's `ctl`
  client resolves "active workspace" by asking the Hyprland IPC socket for its
  client list; this widget never talks to Hyprland itself.

## Requirements

- `terminal-delight` on `PATH`, built with the control socket
  (`feat/td-paint-mode` or later). Terminals started from older builds show a
  brief `🖌∅` on the widget face — reopen them on the new build.
- Hyprland (for the "active workspace" scope; `--all` needs nothing).

## Buttons

| Button | Means |
|---|---|
| Left | paint the terminals on **this** workspace (toggle) |
| Middle | paint **every** terminal on every workspace (toggle) |
| Right | done painting, everywhere |

## Keyboard

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER SHIFT", "P", function()
  hl.dsp.exec_cmd("omarchy-shell brownfamilysports.td-palette toggle")
end)
```

## Install

```bash
omarchy plugin add https://github.com/parker-brown-family/omarchy-td-palette.git --enable
```

(Until graduation this plugin lives in the lab's incubator and is dev-linked;
the URL above goes live when it ships.)

MIT.
