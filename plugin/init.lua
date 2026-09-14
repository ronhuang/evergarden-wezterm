--[[
evergarden for WezTerm

Registers all 5 evergarden flavors x 12 accents as WezTerm color schemes and
adds Command Palette entries (and bindable actions) for switching between them
at runtime.

    local eg = wezterm.plugin.require 'https://codeberg.org/evergarden/wezterm'
    eg.apply_to_config(config, { flavor = 'fall', accent = 'green' })

The palette data lives in plugin/palettes.lua, which is generated from the
evergarden nvim palettes by scripts/build-palettes.mjs.
]]

local wezterm = require 'wezterm'

local M = {}

----------------------------------------------------------------------------
-- Palette data
----------------------------------------------------------------------------

-- Locate plugin/palettes.lua without hardcoding our own git url.
--
-- `debug` is not available in wezterm's Lua sandbox, so the directory of the
-- currently executing file cannot be recovered. `wezterm.plugin.list()` is the
-- documented way to find plugin directories; probing for our own generated
-- file (rather than keying off the url) keeps `file://` development checkouts
-- and forks working without edits.
local function load_palettes()
  local sep = package.config:sub(1, 1)
  for _, entry in ipairs(wezterm.plugin.list()) do
    local path = entry.plugin_dir .. sep .. 'plugin' .. sep .. 'palettes.lua'
    local chunk = loadfile(path)
    if chunk then
      local ok, data = pcall(chunk)
      if ok and type(data) == 'table' and type(data.flavors) == 'table' then
        return data
      end
    end
  end
  error(
    'evergarden: unable to find plugin/palettes.lua. '
      .. 'Try `wezterm.plugin.update_all()`, or remove the plugin directory and reload.'
  )
end

local palettes = load_palettes()

--- Flavor identifiers in cycle order: winter, fall, spring, summer, lunar.
M.flavors = palettes.order

--- Accent identifiers in cycle order.
M.accents = palettes.accents

--- Raw per-flavor color tables, keyed by flavor identifier.
M.palettes = palettes.flavors

local accent_set = {}
for _, accent in ipairs(M.accents) do
  accent_set[accent] = true
end

local function validate(flavor, accent)
  if not palettes.flavors[flavor] then
    error(
      ('evergarden: unknown flavor %q (expected one of %s)')
        :format(tostring(flavor), table.concat(M.flavors, ', '))
    )
  end
  if not accent_set[accent] then
    error(
      ('evergarden: unknown accent %q (expected one of %s)')
        :format(tostring(accent), table.concat(M.accents, ', '))
    )
  end
end

----------------------------------------------------------------------------
-- Scheme construction
----------------------------------------------------------------------------

local function scheme_name(flavor, accent)
  return 'evergarden-' .. flavor .. '-' .. accent
end

--- Build the WezTerm color scheme for a flavor/accent pair.
--
-- This mirrors the conventions used by the other evergarden terminal ports
-- (ghostty, kitty, alacritty) so that a given flavor looks the same in every
-- terminal:
--
--   * the ansi palette comes from the flavor's fixed hues and does *not*
--     change with the selected accent;
--   * the accent only drives the cursor and the active tab.
function M.scheme(flavor, accent)
  validate(flavor, accent)
  local c = palettes.flavors[flavor].colors
  local a = c[accent]
  return {
    foreground = c.text,
    background = c.base,

    cursor_fg = c.crust,
    cursor_bg = a,
    cursor_border = a,

    selection_fg = c.text,
    selection_bg = c.surface1,

    scrollbar_thumb = c.surface2,
    split = c.overlay1,
    visual_bell = a,
    compose_cursor = a,

    -- black, red, green, yellow, blue, magenta, cyan, white
    ansi = { c.base, c.red, c.green, c.yellow, c.blue, c.pink, c.aqua, c.text },
    brights = { c.surface0, c.red, c.green, c.yellow, c.blue, c.pink, c.aqua, c.subtext0 },

    tab_bar = {
      background = c.mantle,
      inactive_tab_edge = c.surface0,
      active_tab = { bg_color = a, fg_color = c.crust, intensity = 'Bold' },
      inactive_tab = { bg_color = c.crust, fg_color = c.overlay1 },
      inactive_tab_hover = { bg_color = c.surface0, fg_color = c.text, italic = true },
      new_tab = { bg_color = c.crust, fg_color = c.overlay1 },
      new_tab_hover = { bg_color = c.surface0, fg_color = c.text, italic = true },
    },
  }
end

-- `window_frame` is a top-level config option rather than part of a color
-- scheme, so it can't live in the scheme tables above.
local function frame_colors(flavor, accent)
  local c = palettes.flavors[flavor].colors
  local a = c[accent]
  return {
    active_titlebar_bg = c.mantle,
    inactive_titlebar_bg = c.crust,
    active_titlebar_fg = c.text,
    inactive_titlebar_fg = c.overlay0,
    active_titlebar_border_bottom = a,
    inactive_titlebar_border_bottom = c.surface0,
    button_fg = c.overlay1,
    button_bg = c.crust,
    button_hover_fg = c.text,
    button_hover_bg = c.surface0,
  }
end

----------------------------------------------------------------------------
-- Runtime state
----------------------------------------------------------------------------

local plugin_opts = {
  -- window_frame keys supplied by the user, preserved across rotations
  frame = {},
  notifications = true,
}

-- The scheme selected in wezterm.lua, used as the starting point when a window
-- has no override of its own yet.
local default_scheme

local function parse_scheme(name)
  if type(name) ~= 'string' then
    return nil
  end
  local flavor, accent = name:match '^evergarden%-(%a+)%-(%a+)$'
  if flavor and palettes.flavors[flavor] and accent_set[accent] then
    return flavor, accent
  end
  return nil
end

--- Find where the given window currently is.
--
-- A rotation applied earlier in this window is recorded in the window's config
-- overrides; otherwise the window is still on the scheme chosen in wezterm.lua,
-- which is visible through its effective config.
local function current(window)
  local overrides = window:get_config_overrides() or {}
  local flavor, accent = parse_scheme(overrides.color_scheme)
  if flavor then
    return flavor, accent
  end

  local ok, effective = pcall(function()
    return window:effective_config()
  end)
  if ok and type(effective) == 'table' then
    flavor, accent = parse_scheme(effective.color_scheme)
    if flavor then
      return flavor, accent
    end
  end

  return parse_scheme(default_scheme)
end

--- Apply a flavor/accent pair to a single window.
--
-- WezTerm has no way to change colors globally at runtime, so rotation is
-- per-window via config overrides. To make a choice stick, put it in
-- wezterm.lua.
local function apply(window, flavor, accent)
  validate(flavor, accent)

  -- Emit the toast first: set_config_overrides() re-evaluates the config file
  -- several times over, and anything queued after it waits for that work.
  if plugin_opts.notifications then
    window:toast_notification(
      'evergarden',
      palettes.flavors[flavor].name .. ' \194\183 ' .. accent,
      nil,
      1500
    )
  end

  -- A window_frame override replaces the whole table, so re-apply the user's
  -- own window_frame options (font, font_size, ...) alongside our colors.
  local frame = {}
  for k, v in pairs(plugin_opts.frame) do
    frame[k] = v
  end
  for k, v in pairs(frame_colors(flavor, accent)) do
    frame[k] = v
  end

  local ok, err = pcall(function()
    window:set_config_overrides {
      color_scheme = scheme_name(flavor, accent),
      window_frame = frame,
    }
  end)
  if not ok then
    -- A user-supplied window_frame value the window can't round-trip shouldn't
    -- be able to break theme switching.
    wezterm.log_error('evergarden: window_frame override failed: ' .. tostring(err))
    window:set_config_overrides {
      color_scheme = scheme_name(flavor, accent),
    }
  end
end

----------------------------------------------------------------------------
-- Rotation
----------------------------------------------------------------------------

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
  return 1
end

local function shift(list, value, delta)
  local i = index_of(list, value)
  return list[((i - 1 + delta) % #list) + 1]
end

--- Work out the flavor/accent a rotation would move to.
--
-- `kind` is one of `'theme'` (walk all 60 combinations), `'accent'`,
-- `'flavor'` or `'random'`. Both axes wrap around.
--
-- @return flavor, accent
function M.next(flavor, accent, kind, delta)
  delta = delta or 1
  if kind == 'accent' then
    return flavor, shift(M.accents, accent, delta)
  elseif kind == 'flavor' then
    return shift(M.flavors, flavor, delta), accent
  elseif kind == 'random' then
    return M.flavors[math.random(#M.flavors)], M.accents[math.random(#M.accents)]
  end

  -- 'theme': walk every flavor/accent combination as a single sequence.
  local flavor_i = index_of(M.flavors, flavor)
  local accent_i = index_of(M.accents, accent) + delta
  while accent_i > #M.accents do
    accent_i = accent_i - #M.accents
    flavor_i = flavor_i % #M.flavors + 1
  end
  while accent_i < 1 do
    accent_i = accent_i + #M.accents
    flavor_i = (flavor_i - 2) % #M.flavors + 1
  end
  return M.flavors[flavor_i], M.accents[accent_i]
end

--- Table of action constructors, for use in `config.keys`.
--
--   eg.action.rotate('accent', 1)   -- next accent
--   eg.action.rotate('flavor', -1)  -- previous flavor
--   eg.action.rotate('theme', 1)    -- next of all 60 combinations
--   eg.action.rotate('random')      -- random combination
--   eg.action.set('summer', 'blue') -- a specific combination
M.action = {}

function M.action.rotate(kind, delta)
  return wezterm.action_callback(function(window)
    local flavor, accent = current(window)
    flavor = flavor or 'fall'
    accent = accent or 'green'
    local next_flavor, next_accent = M.next(flavor, accent, kind, delta)
    apply(window, next_flavor, next_accent)
  end)
end

function M.action.set(flavor, accent)
  return wezterm.action_callback(function(window)
    apply(window, flavor, accent)
  end)
end

local function pick(kind)
  local choices = {}
  for _, item in ipairs(kind == 'accent' and M.accents or M.flavors) do
    choices[#choices + 1] = {
      id = item,
      label = kind == 'accent' and item or palettes.flavors[item].name,
    }
  end

  return wezterm.action.InputSelector {
    title = 'Evergarden ' .. kind,
    choices = choices,
    action = wezterm.action_callback(function(window, pane, id)
      if not id then
        return
      end
      local flavor, accent = current(window)
      flavor = flavor or 'fall'
      accent = accent or 'green'
      if kind == 'accent' then
        accent = id
      else
        flavor = id
      end
      apply(window, flavor, accent)
    end),
  }
end

----------------------------------------------------------------------------
-- Command Palette
----------------------------------------------------------------------------

--- Entries added to the Command Palette (Ctrl+Shift+P).
function M.command_palette_entries()
  return {
    {
      brief = 'Evergarden: next theme',
      doc = 'Cycle to the next flavor/accent combination',
      icon = 'md_palette',
      action = M.action.rotate('theme', 1),
    },
    {
      brief = 'Evergarden: previous theme',
      doc = 'Cycle to the previous flavor/accent combination',
      icon = 'md_palette',
      action = M.action.rotate('theme', -1),
    },
    {
      brief = 'Evergarden: next accent',
      icon = 'md_brush',
      action = M.action.rotate('accent', 1),
    },
    {
      brief = 'Evergarden: previous accent',
      icon = 'md_brush',
      action = M.action.rotate('accent', -1),
    },
    {
      brief = 'Evergarden: next flavor',
      icon = 'md_palette_swatch',
      action = M.action.rotate('flavor', 1),
    },
    {
      brief = 'Evergarden: previous flavor',
      icon = 'md_palette_swatch',
      action = M.action.rotate('flavor', -1),
    },
    {
      brief = 'Evergarden: random theme',
      icon = 'md_dice_multiple',
      action = M.action.rotate('random'),
    },
    {
      brief = 'Evergarden: select flavor',
      doc = 'Pick one of winter, fall, spring, summer or lunar',
      icon = 'md_format_list_bulleted',
      action = pick 'flavor',
    },
    {
      brief = 'Evergarden: select accent',
      doc = 'Pick one of the 12 evergarden accent colors',
      icon = 'md_format_list_bulleted',
      action = pick 'accent',
    },
  }
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

--- Register every evergarden scheme and select one.
--
-- Call this *after* setting any `window_frame` options of your own: the plugin
-- owns the window_frame colors and applies them on top of what you set.
--
-- @param config wezterm config builder
-- @param opts? { flavor?: string, accent?: string, notifications?: boolean }
function M.apply_to_config(config, opts)
  opts = opts or {}
  local flavor = opts.flavor or 'fall'
  local accent = opts.accent or 'green'
  validate(flavor, accent)

  plugin_opts.notifications = opts.notifications ~= false

  -- Remember the user's non-color window_frame options (font, font_size, ...)
  -- so that rotations, which replace the whole table, don't drop them.
  plugin_opts.frame = {}
  for k, v in pairs(config.window_frame or {}) do
    plugin_opts.frame[k] = v
  end

  config.color_schemes = config.color_schemes or {}
  for _, f in ipairs(M.flavors) do
    for _, a in ipairs(M.accents) do
      config.color_schemes[scheme_name(f, a)] = M.scheme(f, a)
    end
  end

  config.window_frame = config.window_frame or {}
  for k, v in pairs(frame_colors(flavor, accent)) do
    config.window_frame[k] = v
  end

  config.color_scheme = scheme_name(flavor, accent)
  default_scheme = config.color_scheme

  wezterm.on('augment-command-palette', function()
    return M.command_palette_entries()
  end)
end

return M
