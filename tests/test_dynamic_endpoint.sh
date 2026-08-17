#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' 0 1 2 15

# Loading with a non-command leaves the production functions available.
busybox=busybox
export busybox
set -- __test_source__
# shellcheck disable=SC1091
. "$repo_dir/wgksu" >/dev/null
wg_data="$test_tmp/data"
mkdir -p "$wg_data"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# These replace functions loaded dynamically from wgksu.
# shellcheck disable=SC2317
probe_native_ipv6() { return 0; }
# shellcheck disable=SC2317
resolve_host6() { echo '2001:db8::10'; }
# shellcheck disable=SC2317
resolve_txt() { echo '198.51.100.20:45678'; }

choice=$(select_dynamic_candidate ipv6.rannj.top 51820 ipv4.rannj.top "")
[ "$choice" = 'NATIVE_V6|[2001:db8::10]:51820' ] || fail "unexpected IPv6 choice: $choice"

# shellcheck disable=SC2317
probe_native_ipv6() { return 1; }
choice=$(select_dynamic_candidate ipv6.rannj.top 51820 ipv4.rannj.top "")
[ "$choice" = 'NATMAP_V4|198.51.100.20:45678' ] || fail "unexpected NATMap choice: $choice"

input="$test_tmp/input.conf"
output="$test_tmp/output.conf"
cat > "$input" <<'EOF'
[Interface]
PrivateKey = private
[Peer]
PublicKey = public
Endpoint = ipv6.rannj.top:51820
EndpointFallbackTXT = ipv4.rannj.top
AllowedIPs = 10.0.0.0/24
EOF
prepare_dynamic_endpoint_config "$input" "$output" wg0
grep -Fqx 'Endpoint = 198.51.100.20:45678' "$output" || fail "prepared endpoint is wrong"
if grep -q EndpointFallbackTXT "$output"; then
  fail "custom key leaked into wg setconf input"
fi
grep -Fqx 'public|NATMAP_V4|198.51.100.20:45678|ipv6.rannj.top|ipv4.rannj.top|51820' \
  "$wg_data/dynamic-endpoint.wg0" || fail "fixed native port was not retained"

plain="$test_tmp/plain.conf"
plain_output="$test_tmp/plain-output.conf"
sed '/EndpointFallbackTXT/d' "$input" > "$plain"
prepare_dynamic_endpoint_config "$plain" "$plain_output" wg1
cmp -s "$plain" "$plain_output" || fail "ordinary config changed"

echo "dynamic endpoint selection tests passed"
