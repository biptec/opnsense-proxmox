# Runtime listener verification

Copy `listeners.json`, replace every documentation address and process name with the deployed contract, then run the verifier on OPNsense:

```sh
python3 scripts/verify_listeners.py --contract listeners.json
```

For offline testing or CI, provide captured `sockstat -4 -6 -l` output with `--input`.

The verifier derives all managed protocol/port pairs from the contract. For those pairs it requires every exact endpoint, rejects wildcard or unlisted addresses, and rejects processes outside the allowed list. Unrelated ports are ignored, so local administrative sockets such as the Caddy API can be verified separately.

This check must run after every apply and reboot. A green firewall plan does not compensate for a wildcard service listener.
