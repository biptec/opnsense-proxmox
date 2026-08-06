# Authoritative DNS verification

Copy `contract.json` and replace every documentation address, zone, probe record, and expected value.

Install a current BIND `dig` client on the verification host. Load the dedicated transfer secret from a secret manager without writing it to the contract:

```sh
export DNS_TRANSFER_TSIG_SECRET='<base64 transfer secret>'
python3 scripts/verify_dns.py --contract contract.json
```

The verifier checks both primary and secondary over UDP and TCP, requires authoritative answers, verifies DNSKEY plus RRSIG, rejects recursion, rejects unauthenticated AXFR, verifies authenticated AXFR from the primary, requires DNSSEC-signed NXDOMAIN responses, and waits for matching SOA serials. After publishing delegation, add the optional `delegation` object to verify the exact NS set and parent DS record through an independent resolver.

Run it from an external network after every DNS deployment and reboot. Use a separate internal-view verification contract from an authorized internal client; public and internal behavior must not be inferred from one vantage point.

The generated temporary TSIG key file is mode `0600` and is deleted after use. The secret is still exposed to this process through an environment variable, so run the verifier only on a trusted ephemeral runner and clear the environment afterward.
