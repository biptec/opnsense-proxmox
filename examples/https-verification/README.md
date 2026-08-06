# HTTPS runtime verification

The verifier connects to each configured listener IP directly while sending the configured DNS name as both TLS SNI and the HTTP `Host` header. DNS therefore cannot silently redirect the test to another address.

Copy `contract.json`, replace the documentation addresses, domains, status codes, headers, and body markers, then run:

```sh
python3 scripts/verify_https.py examples/https-verification/contract.json
```

Public certificates use the operating system trust store. Internal certificates must specify an explicit `ca_file`; relative paths are resolved from the contract directory. There is intentionally no insecure TLS mode.

The verifier does not follow redirects. It checks the response returned by the exact listener, including:

- status and exact redirect location;
- required, partial, and forbidden headers;
- required and forbidden body markers;
- certificate hostname/SAN, issuer markers, and remaining validity;
- maximum accepted response-body size.

Use `body_not_contains` and `forbidden_headers` to reject WebGUI responses on Caddy addresses. This complements, but does not replace, the listener and firewall checks.
