#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
POLICY="$ROOT_DIR/src/etc/caddy/caddy.d/10-acme-ca.global"
EXPECTED='acme_ca https://acme-v02.api.letsencrypt.org/directory'

[ -f "$POLICY" ]
[ "$(cat "$POLICY")" = "$EXPECTED" ]
[ "$(wc -l < "$POLICY" | tr -d ' ')" = "1" ]
