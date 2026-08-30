# Terminal Paint

**Give every terminal on the workspace its own Omarchy theme.**

Click the palette in the bar and each terminal tile grows a picker card
holding every theme installed on the box — Osaka Jade, Vantablack, Tokyo
Night, whatever you have — each drawn as a small terminal in that theme's own
background, accent and foreground. Click one and *that tile* wears it. Same
colours the theme grid would put on the whole desktop; the only difference is
how far they reach.

A rail across the top does the workspace at once: SATURATE ALL and RESET
DEFAULTS.

- **foot / Alacritty / kitty / Ghostty / WezTerm** — the card floats over the
  window; a pick runs `td-tint --window <address> --theme <name>`, which
  writes that theme's OSC palette down the terminal's own tty and puts the
  matching gradient on its window border. Runtime-only, dies with the window;
  the ⟲ DESKTOP card hands the tile back to the desktop theme.
- **Terminal Delight** — its story is better than a window tint (per-pane,
  persistent, CRT-identity-preserving), so its card is a single handoff that
  raises TD's own in-app pane picker over its control socket and gets out of
  the way.

Esc, or a click on the dimmed background, or a second click on the palette:
brushes away everywhere.

## What this plugin runs, reads, and sends

Plugins are unsandboxed, so here is the whole footprint:

- **Runs, on summon:** one command — `td-tint --state`, the oracle that reports
  the installed themes and where the terminal tiles are. **Runs, on a card
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

The theme list is not ours in any sense. The names are **directory names**
from `~/.config/omarchy/themes` and Omarchy's own share — anyone's, including
a theme cloned from a stranger's repo an hour ago — and the colours are
whatever that theme's `colors.toml` says. It reaches this plugin over a pipe,
so `--state` output is treated as third-party input and normalised by one
function at one boundary before anything downstream sees it:

| Field | Accepted | Why it matters |
|---|---|---|
| `key` | `^[a-z0-9][a-z0-9-]{0,31}$` | it is an argv word — so it may carry no markup, and may never begin with `-` |
| `label` | plain text, ≤ 28 chars, control characters stripped | drawn, never executed; it is also the letter the keyboard matches |
| `accent`, `partner`, `bg`, `fg` | `#rgb` / `#rrggbb` / `#aarrggbb` | they land in a string→color coercion |
| window address | `^0x[0-9a-f]{1,16}$` | it is the argv word behind `--window`, and a filename inside `td-tint`'s run dir |

A record that does not fit is dropped, not repaired. Card labels are built from
plain `Text` items with font properties — the draw path never assembles markup,
so there is nothing for a hostile name to be rendered as. The snapshot read is
gated on the collector draining rather than on a timer, and a document past
256 KiB is discarded unparsed.

## Requirements

- **`td-tint`** on `PATH`, current enough to report `themes` from
  `td-tint --state` and accept `--theme`
  ([omarchy-terminal-delight-theme](https://github.com/parker-brown-family/omarchy-terminal-delight-theme)
  → `./install-variants.sh` installs it).
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
| any letter | paint the selected tile with the first theme whose name starts with it; press it again to walk to the next match |
| Space | toggle SATURATE on the selected tile |
| Backspace | hand the selected tile back to the desktop theme |
| S | toggle SATURATE ALL |
| R | reset every tile to defaults |
| ⏎ | Terminal Delight's own pane picker |
| Esc | done — brushes away everywhere |

**Letters are names, everything else is a verb.** Every lowercase letter
belongs to a theme, so no verb may take one: `s` would have stolen
`solitude`, `o` would have stolen `osaka-jade`, and `d` was safe only until
someone installs `dracula`. The two workspace-wide verbs sit on shifted
letters, which the name matcher never sees.

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
