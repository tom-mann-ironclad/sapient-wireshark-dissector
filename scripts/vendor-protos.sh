#!/usr/bin/env bash
# Stages a local checkout of DSTL's SAPIENT-Proto-Files (or sapient-rs's own
# vendored copy under proto/) into proto/sapient_msg/... -- the layout the
# schema's own `import "sapient_msg/..."` statements require, and the one
# Wireshark's Protobuf search path preference expects to find them under.
# Mirrors sapient-rs/scripts/regenerate-rust-bindings.sh's own staging step.
#
# Also vendors Google's well-known types (`google/protobuf/timestamp.proto`,
# `google/protobuf/descriptor.proto`) that `sapient_message.proto`/
# `proto_options.proto` import -- confirmed by real testing: Wireshark's
# bundled Protobuf dissector does NOT ship these itself, unlike a full protoc
# install, so without them it fails with "file [google/protobuf/....proto]
# does not exist!" even though the SAPIENT schema itself parses fine.
#
# By default these are fetched from protobuf's v3.17.3 tag, NOT whatever
# `protoc` happens to be installed locally -- confirmed by real testing that
# this matters: Wireshark's own `.proto` text parser is hand-written and
# fairly old, and a modern descriptor.proto (protoc 28.0 was tried) fails
# with "already defined" conflicts it can't parse, while v3.17.3 (roughly
# contemporaneous with Wireshark 3.4.x/4.x's own parser) works. If your
# Wireshark build still rejects it, try a version closer to your own
# Wireshark release's era -- see the second argument below.
#
# Usage: scripts/vendor-protos.sh <path to SAPIENT-Proto-Files or sapient-rs/proto> [path to protobuf well-known-types include dir]
#
# The optional second argument overrides the default (downloading v3.17.3
# from GitHub) with a local include directory instead -- e.g. a specific
# `protoc` install's `include/` you've already confirmed works with your
# Wireshark version.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <path to SAPIENT-Proto-Files or sapient-rs/proto checkout> [path to protobuf well-known-types include dir]" >&2
    exit 1
fi

source_dir="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest_root="$repo_root/proto/sapient_msg"

if [ ! -f "$source_dir/proto_options.proto" ]; then
    echo "error: $source_dir/proto_options.proto not found -- is this a SAPIENT-Proto-Files checkout?" >&2
    exit 1
fi

rm -rf "$dest_root"
mkdir -p "$dest_root"

cp "$source_dir/proto_options.proto" "$dest_root/"
if [ -f "$source_dir/LICENCE.txt" ]; then
    cp "$source_dir/LICENCE.txt" "$repo_root/proto/"
fi

for version_dir in bsi_flex_335_v1_0 bsi_flex_335_v2_0; do
    mkdir -p "$dest_root/$version_dir"
    cp "$source_dir/$version_dir/"*.proto "$dest_root/$version_dir/"
done

echo "Vendored proto files into $dest_root"

well_known_dir="${2:-}"
mkdir -p "$repo_root/proto/google/protobuf"

if [ -n "$well_known_dir" ]; then
    if [ ! -f "$well_known_dir/google/protobuf/timestamp.proto" ]; then
        echo "error: $well_known_dir/google/protobuf/timestamp.proto not found" >&2
        exit 1
    fi
    cp "$well_known_dir/google/protobuf/timestamp.proto" "$repo_root/proto/google/protobuf/"
    cp "$well_known_dir/google/protobuf/descriptor.proto" "$repo_root/proto/google/protobuf/"
    echo "Vendored google/protobuf/{timestamp,descriptor}.proto from $well_known_dir"
else
    pinned_tag="v3.17.3"
    base_url="https://raw.githubusercontent.com/protocolbuffers/protobuf/$pinned_tag/src/google/protobuf"
    curl -fsSL "$base_url/timestamp.proto" -o "$repo_root/proto/google/protobuf/timestamp.proto"
    curl -fsSL "$base_url/descriptor.proto" -o "$repo_root/proto/google/protobuf/descriptor.proto"
    echo "Vendored google/protobuf/{timestamp,descriptor}.proto from protobuf $pinned_tag (verified compatible)"
fi
