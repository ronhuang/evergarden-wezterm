_default:
  @just --list

# Regenerate plugin/palettes.lua from wezterm.tera.
build:
  whiskers wezterm.tera

# Fail if plugin/palettes.lua is out of date. Useful in CI.
check:
  whiskers wezterm.tera --check plugin/palettes.lua