#!/bin/sh
# NATMap -e notify script: publish "IPv4:port" in a Cloudflare TXT record.
# NATMap arguments: public-address public-port ip4p private-port protocol private-address

set -eu

config_file=${NATMAP_DNS_CONFIG:-/etc/natmap-wireguard.conf}
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  . "$config_file"
fi

public_addr=${1:-}
public_port=${2:-}

is_ipv4() {
  echo "$1" | awk -F. '
    NF != 4 { exit 1 }
    { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1 }
  '
}

is_ipv4 "$public_addr" || {
  echo "NATMap returned an invalid public IPv4 address: $public_addr" >&2
  exit 2
}
case "$public_port" in
  ''|*[!0-9]*) echo "NATMap returned an invalid public port: $public_port" >&2; exit 2 ;;
esac
[ "$public_port" -ge 1 ] && [ "$public_port" -le 65535 ] || {
  echo "NATMap public port is outside 1..65535: $public_port" >&2
  exit 2
}

: "${CF_API_TOKEN:?set CF_API_TOKEN in $config_file}"
: "${CF_ZONE_ID:?set CF_ZONE_ID in $config_file}"
: "${CF_DNS_RECORD_ID:?set CF_DNS_RECORD_ID in $config_file}"
CF_RECORD_NAME=${CF_RECORD_NAME:-ipv4.rannj.top}
CF_TTL=${CF_TTL:-60}
endpoint="${public_addr}:${public_port}"

payload=$(printf '{"type":"TXT","name":"%s","content":"%s","ttl":%s}' \
  "$CF_RECORD_NAME" "$endpoint" "$CF_TTL")
response=$(curl -fsS -X PUT \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_DNS_RECORD_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$payload") || {
    echo "Cloudflare TXT update request failed" >&2
    exit 1
  }

echo "$response" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true' || {
  echo "Cloudflare rejected TXT update: $response" >&2
  exit 1
}
echo "updated ${CF_RECORD_NAME} TXT to ${endpoint}"
