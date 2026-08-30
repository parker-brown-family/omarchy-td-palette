# Terminal Paint

A painter's palette in the Omarchy bar. Click it and **every terminal tile on
your active workspace** grows a picker card. Click a colour on a card and
*that tile* takes that identity.

**Two sources, one switch.** The rail at the top of the overlay chooses which
list the cards are drawn from:

- **TERMINAL DELIGHT** — the palette set from
  [Terminal Delight](https://github.com/parker-brown-family/terminal-delight):
  🦇 ☢ 🍒 🌊 🔥 and the rest, one glyph and one hue each, made for telling one
  terminal out of a wall of them.
- **OMARCHY** — every theme installed on the box (Osaka Jade, Vantablack,
  Tokyo Night, whatever you have), each drawn as a swatch of its own
  background, accent and foreground. Same colours the theme grid would put on
  the *whole desktop*, aimed at one tile instead.

Neither is the "off" state of the other, so the control is two segments rather
than a checkbox. Below it, SATURATE ALL and RESET DEFAULTS act on every
paintable tile at once.

- **foot / Alacritty / kitty / Ghostty / WezTerm** — the card floats over the
  window; a pick runs `td-tint --window <address> -- <palette>` or
  `td-tint --window <address> --theme <name>`, which writes that palette's OSC
  down the terminal's own tty and puts the matching gradient on its window
  border. Runtime-only, dies with the window; the ⟲ DESKTOP card hands the
  tile back to the desktop theme.
- **Terminal Delight** — its story is better than a window tint (per-pane,
  persistent, CRT-identity-preserving), so its card is a single handoff that
  raises TD's own in-app pane picker over its control socket and gets out of
  the way.

Esc, or a click on the dimmed background, or a second click on the palette:
brushes away everywhere.

## What this plugin runs, reads, and sends

Plugins are unsandboxed, so here is the whole footprint:

- **Runs, on summon:** one command — `td-tint --state`, the oracle that reports
  both card lists (palettes and installed themes) and where the terminal tiles
  are. **Runs, on a card click:** `td-tint --window …` or
  `terminal-delight ctl paint …`. **Runs, on an
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

Neither card list is ours. Palette keys, glyphs and colours are authored in
whatever theme repository installed them ([variants.toml](https://github.com/parker-brown-family/omarchy-terminal-delight-theme/blob/main/variants.toml)
→ `install-variants.sh`); theme names are **directory names** from
`~/.config/omarchy/themes` and Omarchy's own share — anyone's, including a
theme cloned from a stranger's repo an hour ago. Both reach this plugin over a
pipe, so `--state` output is treated as third-party input and normalised by
one function at one boundary before anything downstream sees it:

| Field | Accepted | Why it matters |
|---|---|---|
| `key` | `^[a-z0-9][a-z0-9-]{0,31}$` | it is an argv word — so it may carry no markup, and may never begin with `-` |
| `label` | plain text, ≤ 28 chars, control characters stripped | drawn, never executed; it is also the letter the keyboard matches |
| `glyph` | plain text, ≤ 8 chars | drawn as `Text.PlainText`; never sniffed, never interpreted. Empty for a theme, which is drawn as a swatch instead |
| `accent`, `partner`, `bg`, `fg` | `#rgb` / `#rrggbb` / `#aarrggbb` | they land in a string→color coercion |
| window address | `^0x[0-9a-f]{1,16}$` | it is the argv word behind `--window`, and a filename inside `td-tint`'s run dir |

A record that does not fit is dropped, not repaired. Card labels are built from
plain `Text` items with font properties — the draw path never assembles markup,
so there is nothing for a hostile name to be rendered as. The snapshot read is
gated on the collector draining rather than on a timer, and a document past
256 KiB is discarded unparsed.

## Requirements

- The Terminal Delight palette set installed
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
| first letter | paint the selected tile with the first card whose name starts with it; press it again to walk to the next match |
| o | switch source — Terminal Delight palettes ⇄ Omarchy themes |
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

**Unlock the screen first.** Not a quirk of this plugin — on Omarchy 4.0.1 with
quickshell 0.3.1, *any* write under `~/.config/omarchy/plugins/` while the
session is locked hot-reloads the shell, which tears down the live session lock
and aborts the shell under the lockscreen. Installing or updating anything is
such a write. The screen stays locked and the shell relaunches on its own, so
you lose the bar for a few seconds rather than your session — but
`omarchy-restart-shell` will then refuse to help you, because it declines to
restart a locked session.

This is upstream: [omarchy#7106](https://github.com/omacom/omarchy/issues/7106)
and [#8647](https://github.com/omacom/omarchy/issues/8647), fixed by the open
[#7572](https://github.com/omacom/omarchy/pull/7572), with the underlying defect
at [quickshell#962](https://github.com/quickshell-mirror/quickshell/issues/962).
It applies to every Omarchy plugin equally. Until #7572 lands, run
`omarchy plugin add` and `omarchy plugin update` against an unlocked session.

## Remove

```bash
omarchy plugin remove brownfamilysports.td-palette --yes
```

Runtime tints die with their windows; the plugin itself writes no state and
leaves nothing behind.

MIT.
