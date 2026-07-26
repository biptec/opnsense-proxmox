#!/bin/sh
set -eu

# This script runs only when wait_for_api=true. It waits for SSH, copies the
# one-time bootstrap API credentials, and verifies a real authenticated request.
: "${SSH_HOST:?SSH_HOST is required}"
: "${SSH_KEY:?SSH_KEY is required}"
: "${API_SCHEME:?API_SCHEME is required}"
: "${API_CREDENTIALS_OUT:?API_CREDENTIALS_OUT is required}"

TMP=$(mktemp -d /tmp/opnsense-ready.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Wait up to 7.5 minutes for first-boot bootstrap and SSH access.
attempt=1
while [ "$attempt" -le 90 ]; do
    if ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "root@$SSH_HOST" \
        'test -s /conf/bootstrap-api.json && cat /conf/bootstrap-api.json' \
        > "$TMP/credentials.json" 2>/dev/null; then
        break
    fi
    sleep 5
    attempt=$((attempt + 1))
done

if [ ! -s "$TMP/credentials.json" ]; then
    echo "Timed out waiting for bootstrap credentials on $SSH_HOST" >&2
    exit 1
fi

# Parse credentials without printing them to stdout or the OpenTofu log.
KEY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key"])' "$TMP/credentials.json")
SECRET=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["secret"])' "$TMP/credentials.json")

# Wait up to 5 minutes for the HTTPS API to become ready.
attempt=1
while [ "$attempt" -le 60 ]; do
    CODE=$(curl -k -sS \
        -o "$TMP/api.json" \
        -w '%{http_code}' \
        -u "$KEY:$SECRET" \
        "$API_SCHEME://$SSH_HOST/api/interfaces/assignment/search_item" \
        2>/dev/null || true)

    if [ "$CODE" = "200" ] && \
        python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/api.json"; then
        mkdir -p "$(dirname "$API_CREDENTIALS_OUT")"
        install -m 0600 "$TMP/credentials.json" "$API_CREDENTIALS_OUT"
        unset KEY SECRET
        echo "OPNsense API is ready at $API_SCHEME://$SSH_HOST"
        exit 0
    fi

    sleep 5
    attempt=$((attempt + 1))
done

unset KEY SECRET
echo "Timed out waiting for OPNsense API on $SSH_HOST" >&2
exit 1
