#!/bin/sh
set -eu

: "${SSH_HOST:?SSH_HOST is required}"
: "${SSH_USER:?SSH_USER is required}"
: "${SSH_KEY:?SSH_KEY is required}"
: "${SSH_WAIT_ATTEMPTS:?SSH_WAIT_ATTEMPTS is required}"
: "${API_WAIT_ATTEMPTS:?API_WAIT_ATTEMPTS is required}"
: "${WAIT_INTERVAL_SECONDS:?WAIT_INTERVAL_SECONDS is required}"
: "${API_SCHEME:?API_SCHEME is required}"
: "${API_ENDPOINT_PATH:?API_ENDPOINT_PATH is required}"
: "${API_CREDENTIALS_OUT:?API_CREDENTIALS_OUT is required}"

TMP=$(mktemp -d /tmp/opnsense-ready.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

printf 'Waiting for SSH and bootstrap credentials on %s@%s\n' "$SSH_USER" "$SSH_HOST"
attempt=1
while [ "$attempt" -le "$SSH_WAIT_ATTEMPTS" ]; do
    if ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$SSH_HOST" \
        'test -s /conf/bootstrap-api.json && cat /conf/bootstrap-api.json' \
        > "$TMP/credentials.json" 2> "$TMP/ssh-error"; then
        break
    fi

    if [ $((attempt % 6)) -eq 0 ]; then
        printf 'Still waiting for SSH/bootstrap credentials (%s/%s)\n' "$attempt" "$SSH_WAIT_ATTEMPTS"
        tail -n 1 "$TMP/ssh-error" 2>/dev/null || true
    fi

    sleep "$WAIT_INTERVAL_SECONDS"
    attempt=$((attempt + 1))
done

if [ ! -s "$TMP/credentials.json" ]; then
    echo "Timed out waiting for bootstrap credentials on $SSH_USER@$SSH_HOST" >&2
    tail -n 1 "$TMP/ssh-error" >&2 2>/dev/null || true
    exit 1
fi

KEY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key"])' "$TMP/credentials.json")
SECRET=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["secret"])' "$TMP/credentials.json")

printf 'Bootstrap credentials received; waiting for OPNsense API at %s://%s%s\n' "$API_SCHEME" "$SSH_HOST" "$API_ENDPOINT_PATH"
attempt=1
while [ "$attempt" -le "$API_WAIT_ATTEMPTS" ]; do
    CODE=$(curl -k -sS \
        -o "$TMP/api.json" \
        -w '%{http_code}' \
        -u "$KEY:$SECRET" \
        "$API_SCHEME://$SSH_HOST$API_ENDPOINT_PATH" \
        2>/dev/null || true)

    if [ "$CODE" = "200" ] && \
        python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/api.json"; then
        mkdir -p "$(dirname "$API_CREDENTIALS_OUT")"
        install -m 0600 "$TMP/credentials.json" "$API_CREDENTIALS_OUT"
        unset KEY SECRET
        echo "OPNsense API is ready at $API_SCHEME://$SSH_HOST"
        exit 0
    fi

    if [ $((attempt % 6)) -eq 0 ]; then
        printf 'Still waiting for authenticated API response (%s/%s, HTTP %s)\n' "$attempt" "$API_WAIT_ATTEMPTS" "${CODE:-none}"
    fi

    sleep "$WAIT_INTERVAL_SECONDS"
    attempt=$((attempt + 1))
done

unset KEY SECRET
echo "Timed out waiting for OPNsense API on $SSH_HOST" >&2
exit 1
