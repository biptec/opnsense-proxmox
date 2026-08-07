#!/usr/bin/env python3
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.request


def fail(message: str) -> None:
    print(json.dumps({"error": message}))
    sys.exit(1)


uri = os.environ.get("OPNSENSE_URI", "").rstrip("/")
api_key = os.environ.get("OPNSENSE_API_KEY", "")
api_secret = os.environ.get("OPNSENSE_API_SECRET", "")
allow_insecure = os.environ.get("OPNSENSE_ALLOW_INSECURE", "false").lower() in {"1", "true", "yes", "on"}

if not uri or not api_key or not api_secret:
    fail("OPNSENSE_URI, OPNSENSE_API_KEY, and OPNSENSE_API_SECRET must be set")

endpoint = uri + "/api/api_extensions/webgui/get"
credentials = base64.b64encode(f"{api_key}:{api_secret}".encode()).decode()
request = urllib.request.Request(endpoint, headers={"Authorization": "Basic " + credentials})
context = ssl._create_unverified_context() if allow_insecure else ssl.create_default_context()

try:
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        payload = json.load(response)
except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
    fail(f"unable to read current WebGUI settings: {exc}")

certificate_ref = str(payload.get("webgui", {}).get("certificate_ref", "")).strip()
if not certificate_ref:
    fail("current WebGUI settings do not contain a certificate_ref")

print(json.dumps({"certificate_ref": certificate_ref}))
