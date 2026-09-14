_default:
  @just --list

# Regenerate plugin/palettes.lua from the upstream evergarden palettes.
build:
  node scripts/build-palettes.mjs

# Fail if plugin/palettes.lua is out of date. Useful in CI.
check:
  node scripts/build-palettes.mjs --check
