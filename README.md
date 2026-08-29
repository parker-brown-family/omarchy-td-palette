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

- **Runs, on summon:** one command — `td-tint --state`, the oracle that reports
  the installed variant list and where the terminal tiles are. **Runs, on a card
  click:** `td-tint --window …` or `terminal-delight ctl paint …`. **Runs, on an
  empty workspace:** one transient `notify-send` saying so. Nothing resident,
  nothing polled.
- **Every one of those is an argv array.** No `bash -c`, no shell string, no
  string-form `execDetached` anywhere in the file — there is no place for a
  word to be re-split or re-interpreted on its way to a process.
- **Reads:** nothing beyond those command outputs. **Writes:** nothing.
  **Network:** none, ever.
- While the overlay is up it holds exclusive keyboard focus (that is what
  makes Esc work); it releases everything on dismiss.

### What it trusts, and what it checks

The variant set is not ours. Keys, glyphs and colours are authored in whatever
theme repository installed them ([variants.toml](https://github.com/parker-brown-family/omarchy-terminal-delight-theme/blob/main/variants.toml)
→ `install-variants.sh`) and reach this plugin over a pipe, so `--state` output
is treated as third-party input and normalised at one boundary before anything
downstream sees it:

| Field | Accepted | Why it matters |
|---|---|---|
| `key` | `^[a-z0-9][a-z0-9-]{0,31}$` | it is the card label, the keyboard letter **and** an argv word — so it may carry no markup, and may never begin with `-` |
| `glyph` | plain text, ≤ 8 chars | drawn as `Text.PlainText`; never sniffed, never interpreted |
| `accent`, `partner` | `#rgb` / `#rrggbb` / `#aarrggbb` | they land in a string→color coercion |
| window address | `^0x[0-9a-f]{1,16}$` | it is the argv word behind `--window`, and a filename inside `td-tint`'s run dir |

A record that does not fit is dropped, not repaired. Card labels are built from
plain `Text` items with font properties — the draw path never assembles markup,
so there is nothing for a hostile name to be rendered as. The snapshot read is
gated on the collector draining rather than on a timer, and a document past
256 KiB is discarded unparsed.

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

Summon it from a chord (this exact line is what we run):

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + ALT + P", "Paint terminals",
  "omarchy-shell shell toggle brownfamilysports.td-palette")
```

Pick any free chord — `omarchy menu keybindings --print` lists what's taken.

While the overlay is up it plays entirely from the keyboard:

| Key | Means |
|---|---|
| ← → ↑ ↓ / Tab | walk the tiles in reading order |
| first letter | paint the selected tile — every variant owns its own letter |
| d | hand the selected tile back to the desktop theme |
| s | toggle SATURATE on the selected tile |
| S | toggle SATURATE ALL |
| R | reset every tile to defaults |
| ⏎ | Terminal Delight's own pane picker |
| Esc | done — brushes away everywhere |

## The three repos

| Repo | What it is |
|---|---|
| [**terminal-delight**](https://github.com/parker-brown-family/terminal-delight) | the terminal itself — GPU-native, Rust, tiling panes, per-pane grading |
| [**omarchy-terminal-delight-theme**](https://github.com/parker-brown-family/omarchy-terminal-delight-theme) | the desktop half — the Omarchy theme, the variant set, the compositor curve, and `td-tint` |
| [**omarchy-td-palette**](https://github.com/parker-brown-family/omarchy-td-palette) | *Terminal Paint* — this repo, the 🎨 bar widget |

This one is the thinnest: a single QML file that renders what
`td-tint --state` reports and shells out to `td-tint` to act. It authors no
colours and holds no state. That is also why it validates everything it reads
— the variant set is written in the theme repo, which makes it third-party
input here.

## Install

```bash
omarchy plugin add https://github.com/parker-brown-family/omarchy-td-palette.git --enable
```

## Remove

```bash
omarchy plugin remove brownfamilysports.td-palette --yes
```

Runtime tints die with their windows; the plugin itself writes no state and
leaves nothing behind.

MIT.
