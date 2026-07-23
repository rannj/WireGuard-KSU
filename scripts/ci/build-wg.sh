#!/bin/sh

set -eu

workspace=${GITHUB_WORKSPACE:-$(pwd)}
tools_version=$(cat "$workspace/CORE_VERSION")
case "$tools_version" in
  ""|*[!0-9.]*)
    echo "Invalid CORE_VERSION: $tools_version" >&2
    exit 1
    ;;
esac

tools_tag="v${tools_version}"
build_dir=$(mktemp -d)

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup 0 1 2 15

git clone --branch "$tools_tag" --depth 1 \
  https://git.zx2c4.com/wireguard-tools "$build_dir/wireguard-tools"

checked_out_tag=$(git -C "$build_dir/wireguard-tools" describe --tags --exact-match)
if [ "$checked_out_tag" != "$tools_tag" ]; then
  echo "Expected wireguard-tools $tools_tag, got $checked_out_tag" >&2
  exit 1
fi

make -C "$build_dir/wireguard-tools/src" -j"$(nproc)" \
  CC=aarch64-linux-gnu-gcc LDFLAGS="-static" PLATFORM=linux wg
aarch64-linux-gnu-strip "$build_dir/wireguard-tools/src/wg"

file "$build_dir/wireguard-tools/src/wg" | tee "$build_dir/wg-file.txt"
grep -Eq 'ELF 64-bit.*ARM aarch64.*statically linked' "$build_dir/wg-file.txt"

cp "$build_dir/wireguard-tools/src/wg" "$workspace/wg"
