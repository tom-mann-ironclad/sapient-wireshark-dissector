#!/usr/bin/env bash
# Real end-to-end smoke test: wraps the committed real SAPIENT wire bytes
# (see fixtures/README.md) in a synthetic TCP packet, decodes it with the
# actual dissector (loaded ad hoc via `-X lua_script:`, no plugin-folder
# install needed) against the real vendored schema, and checks the output
# for concrete, specific evidence the decode actually worked -- not just
# that tshark exited 0 (which it would for an undecoded raw payload too).
#
# Requires `tshark` with Lua support (`tshark -v | grep -i lua` should say
# "with Lua", not "without"); on Debian/Ubuntu `apt-get install tshark` is
# enough (confirmed on a real Ubuntu 24.04 image: ships with Lua 5.2.4). On
# RHEL/Rocky/CentOS, see the main README's note and
# scripts/build-wireshark-with-lua.sh -- the distro package there is built
# without Lua.
#
# Also requires `hexdump` and `text2pcap`. `text2pcap` ships with
# `tshark`/`wireshark-common`; `hexdump` does NOT ship with a clean Ubuntu
# 24.04 image by default (confirmed directly) -- it's in the
# `bsdextrautils` package there.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/tests/fixtures/registration_v2.sapient-framed.bin"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

for tool in tshark hexdump text2pcap; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool not found on PATH" >&2
        exit 1
    fi
done

# `tshark -v`'s Lua-support line has two real, confirmed-different formats
# across versions -- 3.4.x's prose ("with Lua, ..." / "without Lua, ..."),
# possibly line-wrapped so "with"/"without" and "Lua" land on different
# lines, and 4.x's flag style ("+Lua 5.4.4" / "-Lua"). Flatten to one line
# first so a wrap can't split a check across two `grep` calls.
version_output="$(tshark -v 2>&1 | tr '\n' ' ')"
has_lua=0
if echo "$version_output" | grep -q '+Lua'; then
    has_lua=1
elif echo "$version_output" | grep -qE 'with Lua[, ]' && ! echo "$version_output" | grep -q 'without Lua'; then
    has_lua=1
fi
if [ "$has_lua" -ne 1 ]; then
    echo "error: this tshark was built without Lua support -- can't run this test." >&2
    echo "       tshark -v reported: $version_output" >&2
    exit 1
fi

echo "==> Wrapping the real fixture in a synthetic TCP packet"
port=5000
hexdump -C "$fixture" | text2pcap -T 54321,"$port" - "$work_dir/test.pcap" >/dev/null

echo "==> Decoding with the real dissector against the real vendored schema"
output="$work_dir/decoded.txt"
tshark -r "$work_dir/test.pcap" \
    -X lua_script:"$repo_root/plugins/sapient.lua" \
    -o "uat:protobuf_search_paths:\"$repo_root/proto\",\"TRUE\"" \
    -d tcp.port=="$port",sapient_v2 \
    -V >"$output" 2>"$work_dir/stderr.txt"

if grep -qi "Protobuf: Error" "$work_dir/stderr.txt"; then
    echo "FAIL: tshark reported a Protobuf parsing error:" >&2
    cat "$work_dir/stderr.txt" >&2
    exit 1
fi

fail=0
check() {
    local pattern="$1"
    local description="$2"
    if ! grep -q "$pattern" "$output"; then
        echo "FAIL: expected to find $description (pattern: $pattern)" >&2
        fail=1
    fi
}

# The length field must match the real payload size exactly -- the single
# most direct check that the little-endian prefix is being read correctly
# (a big-endian misread of these particular bytes would produce a wildly
# different, implausible number, not a plausible-but-wrong one).
payload_len=$(($(stat -c%s "$fixture") - 4))
check "Length: $payload_len" "the length field matching the real payload size ($payload_len)"

check "SAPIENT (BSI Flex 335 v2.0)" "the SAPIENT v2.0 protocol name"
check "sapient_msg.bsi_flex_335_v2_0.SapientMessage" "the resolved root message type"
check "node_id = a8654cdf-4328-47de-81fa-c495589e30c9" "the real node_id from the source fixture"
check "destination_id = a8654cdf-4328-47de-81fa-c495589e30c8" "the real destination_id from the source fixture"
check "Message: sapient_msg.bsi_flex_335_v2_0.Registration" "the nested Registration message"

if [ "$fail" -ne 0 ]; then
    echo "--- full decoded output ---" >&2
    cat "$output" >&2
    exit 1
fi

echo "OK: dissector correctly decoded real SAPIENT wire bytes end-to-end"
