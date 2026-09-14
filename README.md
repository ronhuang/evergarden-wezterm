# evergarden for WezTerm

An [evergarden](https://evergarden.moe) port for [WezTerm](https://wezterm.org),
packaged as a WezTerm plugin.

Every flavor and accent is registered as a WezTerm color scheme, and the
Command Palette gains entries for cycling through them at runtime — no restart
and no config edits needed while you look for the combination you like.

```
5 flavors (winter, fall, spring, summer, lunar)
x 12 accents (red, orange, yellow, lime, green, aqua, skye, snow, blue, purple, pink, cherry)
= 60 schemes
```

## Install

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local evergarden = wezterm.plugin.require 'https://codeberg.org/evergarden/wezterm'
evergarden.apply_to_config(config, {
  flavor = 'fall',   -- winter | fall | spring | summer | lunar
  accent = 'green',  -- any accent from the list above
  -- notifications = false, -- silence the toast shown when switching
})

return config
```

This is a personal plugin. Replace the URL with wherever you publish it; to
develop against a local checkout, use a `file:///` URL instead, e.g.
`wezterm.plugin.require 'file:///C:/Users/you/source/repos/evergarden/wezterm'`.

> **Updating:** WezTerm clones a plugin once and never re-fetches it. After the
> plugin repo changes (or after you commit to a local `file:///` checkout), run
> `wezterm.plugin.update_all()` and reload, or delete the plugin directory under
> the WezTerm runtime dir and reload.

## Switching at runtime

Open the Command Palette (`Ctrl+Shift+P` on Windows/Linux) and type
"Evergarden":

| Command | Effect |
| --- | --- |
| Evergarden: next theme | Next of all 60 combinations |
| Evergarden: previous theme | Previous combination |
| Evergarden: next accent | Next accent, same flavor |
| Evergarden: previous accent | Previous accent, same flavor |
| Evergarden: next flavor | Next flavor, same accent |
| Evergarden: previous flavor | Previous flavor, same accent |
| Evergarden: random theme | Random flavor and accent |
| Evergarden: select flavor | Pick from the 5 flavors |
| Evergarden: select accent | Pick from the 12 accents |

Each switch shows a short toast naming the new combination, so you can find the
one you want and then write it into `apply_to_config`.

> **Rotation is per-window.** WezTerm has no runtime API for changing colors
> globally, so switching applies to the window you're in and lasts until that
> window closes. To make a choice stick, put it in `apply_to_config` as shown
> above.

## Keybindings

Switching is palette-only by default, so the plugin never shadows your own
keys. To bind it, use the actions the plugin exports in `config.keys`:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local evergarden = wezterm.plugin.require 'https://codeberg.org/evergarden/wezterm'
evergarden.apply_to_config(config, { flavor = 'fall', accent = 'green' })

-- Rebuild config.keys from scratch here if you set it elsewhere, so these
-- entries aren't dropped.
config.keys = config.keys or {}
local keys = {
  -- cycle every flavor/accent combination
  { key = 'e', mods = 'CTRL|SHIFT', action = evergarden.action.rotate('theme', 1) },
  { key = 'w', mods = 'CTRL|SHIFT', action = evergarden.action.rotate('theme', -1) },

  -- cycle one axis at a time
  { key = 'a', mods = 'CTRL|SHIFT', action = evergarden.action.rotate('accent', 1) },
  { key = 'f', mods = 'CTRL|SHIFT', action = evergarden.action.rotate('flavor', 1) },

  -- pick a known combination
  { key = 'd', mods = 'CTRL|SHIFT', action = evergarden.action.rotate('random') },
  { key = 'n', mods = 'CTRL|SHIFT', action = evergarden.action.set('summer', 'blue') },
}
for _, binding in ipairs(keys) do
  table.insert(config.keys, binding)
end

return config
```

### Action reference

```lua
evergarden.action.rotate('theme', 1)    -- next combination
evergarden.action.rotate('theme', -1)   -- previous combination
evergarden.action.rotate('accent', 1)   -- next accent
evergarden.action.rotate('flavor', -1)  -- previous flavor
evergarden.action.rotate('random')      -- random combination
evergarden.action.set('lunar', 'cherry') -- a specific combination
```

`kind` defaults to `'theme'` and `delta` to `1`. Starting from a window that is
not currently on an evergarden scheme, rotation begins at `fall`/`green`.

### Module reference

```lua
evergarden.flavors      -- { 'winter', 'fall', 'spring', 'summer', 'lunar' }
evergarden.accents      -- { 'red', 'orange', ..., 'cherry' }
evergarden.palettes     -- raw per-flavor colors, e.g. evergarden.palettes.fall.colors.green
evergarden.scheme(f, a) -- build the WezTerm color scheme table for a pair
evergarden.next(f, a, kind, delta) -- where a rotation would land, without applying it
```

## Scheme names

Schemes are named `evergarden-<flavor>-<accent>`, matching the file naming used
by the other evergarden terminal ports, so a preference like
`evergarden-fall-green` means the same thing in Ghostty, Kitty and WezTerm. They
are registered in `config.color_schemes`, so you can also reference them
directly:

```lua
config.color_scheme = 'evergarden-lunar-skye'
```

## What gets colored

The mapping follows the conventions already established by the Ghostty, Kitty
and Alacritty ports, so a flavor looks the same across terminals:

| WezTerm | evergarden |
| --- | --- |
| `foreground` / `background` | `text` / `base` |
| `cursor_bg`, `cursor_border` / `cursor_fg` | accent / `crust` |
| `selection_fg` / `selection_bg` | `text` / `surface1` |
| `scrollbar_thumb` / `split` | `surface2` / `overlay1` |
| `ansi` | `base, red, green, yellow, blue, pink, aqua, text` |
| `brights` | `surface0, red, green, yellow, blue, pink, aqua, subtext0` |
| `tab_bar` | `mantle` background, active tab uses the accent |
| `window_frame` | `mantle`/`crust` titlebar, accent underline |

As in the other terminal ports, **the accent does not change the ANSI palette** —
it only drives the cursor and the active tab. That's what makes switching
accent a cheap, safe operation that never breaks color-dependent terminal
output.

There is deliberately no transparency/opacity support, matching the Ghostty
port.

## Caveats

- **Call `apply_to_config` after setting `window_frame` yourself.** Switching
  replaces the whole `window_frame` table, so the plugin re-applies your
  non-color options (font, font_size, ...) from whatever was present when
  `apply_to_config` ran. Set your `window_frame` first to be safe.
- **Every switch re-evaluates your config file.** That's inherent to WezTerm's
  `window:set_config_overrides()`, which re-runs `wezterm.lua` in a fresh Lua
  state. If your config shells out at load time (for example to locate Visual
  Studio), switching will feel sluggish — memoize that work in `wezterm.GLOBAL`,
  which survives config reloads.
- Requires a WezTerm build new enough for `wezterm.plugin.require` (20230320+),
  `augment-command-palette` (20230712+) and `window:toast_notification`.

## Regenerating the palette

`plugin/palettes.lua` is generated — don't edit it by hand.

```console
$ just build   # node scripts/build-palettes.mjs
$ just check   # fail if it's out of date; useful in CI
```

The generator reads the [evergarden nvim](https://codeberg.org/evergarden/nvim)
palettes, which are the most complete reference: their `winter`, `fall`,
`spring` and `summer` palettes match the `evergarden` Rust crate (v0.1.0) that
Whiskers generates the other ports from, and nvim additionally ships `lunar`,
which the crate does not have yet. Once `lunar` lands in the crate, this could
move to a `wezterm.tera` Whiskers template like the other ports.

The `plugin/` directory layout is required by WezTerm: a plugin must expose
`plugin/init.lua`.

## License

Apache-2.0. The evergarden palette itself is the work of the evergarden
project.
