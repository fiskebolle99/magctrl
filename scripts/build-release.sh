#!/bin/sh
set -eu

magctrl_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
magctrl_cache="$magctrl_root/.build/ModuleCache"

cd "$magctrl_root"
env \
  CLANG_MODULE_CACHE_PATH="$magctrl_cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$magctrl_cache" \
  swift build --disable-sandbox -c release

mkdir -p "$magctrl_root/dist"
cp "$magctrl_root/.build/release/magctrl" "$magctrl_root/dist/magctrl"
chmod 0755 "$magctrl_root/dist/magctrl"
/usr/bin/codesign --force --sign - "$magctrl_root/dist/magctrl"

echo "built $magctrl_root/dist/magctrl"
