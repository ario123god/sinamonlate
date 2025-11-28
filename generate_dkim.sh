#!/usr/bin/env bash
set -euo pipefail

DOMAIN=webiime.ir
SELECTOR=mail
KEYDIR=mail_server/opendkim
mkdir -p "$KEYDIR"

if [[ ! -f .env ]]; then
  echo "Missing .env file with CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID" >&2
  exit 1
fi
source .env

opendkim-genkey -b 2048 -d "$DOMAIN" -s "$SELECTOR" -D "$KEYDIR"
cat "$KEYDIR/$SELECTOR.private" > "$KEYDIR/mail.private"
cat "$KEYDIR/$SELECTOR.txt" > "$KEYDIR/mail.txt"

TXT_RECORD=$(sed -n 's/^.*(\\"\(.*\)\\").*$/\1/p' "$KEYDIR/$SELECTOR.txt")

python3 - "$CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_ZONE_ID" "$TXT_RECORD" <<'PY'
import json
import sys
import urllib.request

token, zone, value = sys.argv[1:4]
url = f"https://api.cloudflare.com/client/v4/zones/{zone}/dns_records"
payload = {
    "type": "TXT",
    "name": "mail._domainkey",
    "content": value,
    "ttl": 3600,
    "proxied": False,
}
req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
})
with urllib.request.urlopen(req) as resp:
    print(resp.read().decode())
PY

echo "DKIM key generated and uploaded to Cloudflare"
