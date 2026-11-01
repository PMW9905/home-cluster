#!/usr/bin/env bash
# Register schematic.yaml with the Talos Image Factory, then download the matching ISO.
#
# Usage:  ./get-iso.sh [talos-version]
#   talos-version  defaults to talosVersion from topf.yaml (e.g. 1.14.5 or v1.14.5)
#
# Optional environment overrides: SCHEMATIC, TOPF_CONFIG, FACTORY, ARCH, OUT_DIR
set -euo pipefail

cd "$(dirname "$0")"

SCHEMATIC="${SCHEMATIC:-schematic.yaml}"
TOPF_CONFIG="${TOPF_CONFIG:-topf.yaml}"
FACTORY="${FACTORY:-https://factory.talos.dev}"
ARCH="${ARCH:-amd64}"
OUT_DIR="${OUT_DIR:-.}"

[[ -f "$SCHEMATIC" ]] || { echo "error: $SCHEMATIC not found" >&2; exit 1; }

# Talos version: argument first, otherwise read it from topf.yaml.
version="${1:-}"
if [[ -z "$version" ]]; then
  [[ -f "$TOPF_CONFIG" ]] || { echo "error: no version given and $TOPF_CONFIG not found" >&2; exit 1; }
  version="$(sed -n 's/^talosVersion:[[:space:]]*//p' "$TOPF_CONFIG" | head -n 1 | tr -d "\"' \r")"
  [[ -n "$version" ]] || { echo "error: talosVersion not found in $TOPF_CONFIG" >&2; exit 1; }
fi
[[ "$version" == v* ]] || version="v$version"   # factory URLs use the v prefix

echo "Registering $SCHEMATIC with $FACTORY ..."
response="$(curl -fsS -X POST --data-binary @"$SCHEMATIC" "$FACTORY/schematics")"
id="$(printf '%s' "$response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{64\}\)".*/\1/p')"
[[ -n "$id" ]] || { echo "error: could not parse a schematic ID from: $response" >&2; exit 1; }

url="$FACTORY/image/$id/$version/metal-$ARCH.iso"
mkdir -p "$OUT_DIR"
out="$OUT_DIR/talos-$version-metal-$ARCH-${id:0:8}.iso"

echo "Schematic ID: $id"
echo "Talos version: $version"
echo "Downloading:  $url"
curl -fL -C - --progress-bar -o "$out" "$url"

echo
echo "Saved: $out"
echo "Flash it (replace /dev/sdX, check with lsblk first - this erases the stick):"
echo "  sudo dd if=\"$out\" of=/dev/sdX bs=4M status=progress conv=fsync"
