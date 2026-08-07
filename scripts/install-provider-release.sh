#!/bin/sh
set -eu

version=${PROVIDER_VERSION:?PROVIDER_VERSION is required}
sha256=${PROVIDER_SHA256:?PROVIDER_SHA256 is required}
mirror_root=${PROVIDER_MIRROR_DIR:?PROVIDER_MIRROR_DIR is required}
archive="terraform-provider-opnsense_${version}_linux_amd64.zip"
release_url="https://github.com/biptec/terraform-provider-opnsense/releases/download/v${version}/${archive}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

curl -fsSL "$release_url" -o "$tmp/$archive"
printf '%s  %s\n' "$sha256" "$tmp/$archive" | sha256sum -c -

target="$mirror_root/registry.opentofu.org/biptec/opnsense/$version/linux_amd64"
rm -rf "$target"
mkdir -p "$target"
unzip -q "$tmp/$archive" -d "$target"

test -x "$target/terraform-provider-opnsense_v${version}"
printf 'Installed provider v%s into %s\n' "$version" "$target"
