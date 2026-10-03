#!/usr/bin/env bash
# Builds Wireshark/tshark from source with Lua dissector support, for
# distros (RHEL, Rocky Linux, CentOS Stream, and other EL-family systems)
# whose packaged `wireshark`/`wireshark-cli` is compiled `without Lua` by
# policy -- confirmed directly: `tshark -v` on Rocky Linux 9.6's own
# `wireshark-cli-3.4.10-9.el9` package reports "without Lua". Without Lua,
# this repo's plugins/sapient.lua dissector can never load, full stop --
# this isn't a configuration problem on your end, it's a missing feature in
# the distro build.
#
# Installs to /usr/local rather than overwriting the distro package at
# /usr/bin, so both coexist and `dnf`'s own bookkeeping for the RPM stays
# intact. Use /usr/local/bin/tshark (or put it first in PATH) afterwards.
#
# This needs sudo (for package installation and `make install`) and takes
# a while to compile -- run it yourself rather than expecting any automated
# agent to do this unattended. CLI tools only by default (no Qt GUI); drop
# `-DBUILD_wireshark=OFF` below if you also want the full Wireshark app.
#
# Usage: scripts/build-wireshark-with-lua.sh [wireshark version tag, e.g. v4.6.9]

set -euo pipefail

version="${1:-v4.6.9}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "==> Enabling EPEL and CRB (Rocky/RHEL/CentOS split many -devel packages out of the default repos)"
if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y epel-release
    sudo dnf config-manager --set-enabled crb || sudo dnf config-manager --set-enabled powertools || true
fi

echo "==> Installing Wireshark's own build dependencies (includes lua-devel) for $version"
curl -fsSL "https://gitlab.com/wireshark/wireshark/-/raw/$version/tools/rpm-setup.sh" -o "$work_dir/rpm-setup.sh"
chmod +x "$work_dir/rpm-setup.sh"
sudo "$work_dir/rpm-setup.sh"

echo "==> Cloning wireshark $version"
git clone --branch "$version" --depth 1 https://gitlab.com/wireshark/wireshark.git "$work_dir/wireshark"

echo "==> Building (tshark/tools only, no Qt GUI)"
mkdir -p "$work_dir/wireshark/build"
cd "$work_dir/wireshark/build"
cmake -DBUILD_wireshark=OFF -DCMAKE_INSTALL_PREFIX=/usr/local ..
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "==> Verifying"
if /usr/local/bin/tshark -v | grep -qi "with Lua"; then
    echo "tshark built with Lua support: /usr/local/bin/tshark"
else
    echo "warning: /usr/local/bin/tshark still reports 'without Lua' -- check the" >&2
    echo "         cmake output above for why lua-devel wasn't detected." >&2
    exit 1
fi
