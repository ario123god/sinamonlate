#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Missing .env file with CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID" >&2
  exit 1
fi
source .env

API=https://api.cloudflare.com/client/v4
headers=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

create_record() {
  local type=$1 name=$2 content=$3 proxied=$4 priority=${5:-}
  data=$(jq -n --arg type "$type" --arg name "$name" --arg content "$content" --argjson proxied $proxied '{type:$type,name:$name,content:$content,proxied:$proxied}')
  if [[ -n "$priority" ]]; then
    data=$(echo "$data" | jq --argjson p "$priority" '. + {priority: ($p|tonumber)}')
  fi
  curl -s -X POST "$API/zones/$CLOUDFLARE_ZONE_ID/dns_records" "${headers[@]}" --data "$data" >/dev/null
}

create_record A mail 5.57.34.95 false
create_record MX webiime.ir mail.webiime.ir false 10
create_record TXT webiime.ir "v=spf1 ip4:5.57.34.95 mx a ~all" false
create_record TXT _dmarc "v=DMARC1; p=quarantine; rua=mailto:admin@webiime.ir" false

if [[ -f mail_server/opendkim/mail.txt ]]; then
  dkim_value=$(tr -d '\n' < mail_server/opendkim/mail.txt | sed 's/"//g')
  create_record TXT mail._domainkey "$dkim_value" false
fi

echo "DNS records pushed to Cloudflare"
