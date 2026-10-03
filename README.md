# sapient-wireshark-dissector

A Wireshark dissector for the SAPIENT / BSI Flex 335 protocol. Decodes
SAPIENT's protobuf messages directly in Wireshark's packet tree, so you can
inspect real traffic between an Edge Node, Fusion Node, DMM, or this
project's own [`sapient-test-harness`](https://github.com/tom-mann-ironclad/sapient-test-harness)
without reaching for a separate tool.

This isn't a hand-written decoder: it's a thin Lua shim (~90 lines, see
[`plugins/sapient.lua`](plugins/sapient.lua)) over Wireshark's own built-in
Protobuf dissector, pointed at the real SAPIENT `.proto` schema. The only
thing the shim does is peel off SAPIENT's wire framing -- a 4-byte
**little-endian** length prefix before each message -- before handing the
payload to Wireshark's generic protobuf decoder. That's also the one detail
that differs from Wireshark's own published example for this pattern (which
uses a big-endian prefix), so it's worth knowing if you ever need to adapt
this further.

## Install

Two one-time steps: tell Wireshark where the `.proto` schema lives, and put
the dissector script in your plugins folder.

### 1. Point Wireshark at the schema

In Wireshark: **Edit → Preferences → Protocols → ProtoBuf**, then under
**Protobuf search paths**, add an entry for this repo's `proto/` directory
and make sure **Load all files** is checked for it. Apply, then restart
Wireshark (or `Analyze → Reload Lua Plugins` plus `Enabled Protocols` once
preferences are reapplied).

This is the same on Windows, Linux, and macOS -- it's a Wireshark
preference, not a filesystem path specific to your OS.

### 2. Install the dissector script

Copy [`plugins/sapient.lua`](plugins/sapient.lua) into your **personal Lua
Plugins folder** -- confirmed via `tshark -G folders` on a real 4.6.9 build
to be **unversioned**, distinct from the personal (binary) Plugins folder,
which *is* version-numbered (e.g. `plugins/4.6/`). Dropping `sapient.lua`
into the versioned folder by mistake still gets picked up on some builds,
but don't rely on that -- use the unversioned one. The definitive location
for your specific build is shown in **Help → About Wireshark → Folders**
(look for "Personal Lua Plugins" specifically, not "Personal Plugins") --
paths have moved between Wireshark versions, so that's the one source
that's always right. As of recent (4.x) Wireshark releases, it's typically:

- **Windows:** `%APPDATA%\Wireshark\plugins\`
- **Linux:** `~/.local/lib/wireshark/plugins/`
- **macOS:** `~/.local/lib/wireshark/plugins/` (same as Linux for the
  official `.app`/Homebrew builds; check the Folders dialog above if
  that's empty on your install)

Create the folder if it doesn't exist, drop `sapient.lua` in, then
**Analyze → Reload Lua Plugins** (or restart Wireshark).

> **On RHEL, Rocky Linux, or CentOS:** the distro-packaged
> `wireshark`/`wireshark-cli` is compiled **without Lua support** --
> confirmed directly (`tshark -v` on Rocky Linux 9.6's own
> `wireshark-cli-3.4.10-9.el9` reports "without Lua"). If that's what you
> have, this dissector can never load, no matter where you put the file --
> check with `tshark -v | grep -i lua` before troubleshooting anything
> else. [`scripts/build-wireshark-with-lua.sh`](scripts/build-wireshark-with-lua.sh)
> builds a current Wireshark from source with Lua enabled, installed to
> `/usr/local` alongside (not over) the distro package.

### 3. Decode a capture

Lua plugins register for "Decode As", not a default port (SAPIENT doesn't
mandate one). On a TCP stream carrying SAPIENT traffic: right-click a
packet → **Decode As...** → set the protocol to **SAPIENT (BSI Flex 335
v2.0)** (or **v1.0**, if that's what you're capturing) → **OK**. The stream
should now show decoded `SapientMessage` fields in the packet detail pane.

## Updating the vendored schema

`proto/` is a vendored copy of DSTL's
[SAPIENT-Proto-Files](https://github.com/dstl/SAPIENT-Proto-Files),
re-staged into the `sapient_msg/...` directory layout the schema's own
`import` statements expect (the same staging
[`sapient-rs`](https://github.com/tom-mann-ironclad/sapient-bindings)
does when generating language bindings). Refresh it from a local checkout
of either SAPIENT-Proto-Files or `sapient-rs/proto` with:

```bash
scripts/vendor-protos.sh /path/to/SAPIENT-Proto-Files
```

## Status

Verified end-to-end against a real Wireshark build (4.6.9, Lua
5.4.4) and real SAPIENT wire bytes -- a genuine fixture, encoded with
`sapient-conformance-core`'s own encoder and framed exactly as the wire
format requires, not hand-crafted:

- `plugins/sapient.lua` loads cleanly, registers both **SAPIENT (BSI Flex
  335 v2.0)** and **v1.0** as Decode As targets, and correctly strips the
  little-endian length prefix -- confirmed by packing *two* framed messages
  into a single TCP segment and seeing both decode independently with the
  right byte offsets, not just a single-message happy path.
- The full, **unmodified** vendored schema -- both v1.0 and v2.0, with
  "Load all files" on -- parses with zero errors. (An earlier test against
  an old distro-packaged Wireshark 3.4.10 hit real-looking parser errors on
  some of DSTL's own syntax, e.g. `reserved` inside `enum` blocks; those
  turned out to be a limitation of that specific old build, not a real
  schema problem -- a current Wireshark handles it fine, and nothing in
  `proto/` needed patching.)
- Decoded output matches the source fixture field-for-field: node IDs,
  timestamps, nested `Registration` content, enum values resolved to their
  named constants (e.g. `NODE_TYPE_CAMERA(4)`, not a bare `4`).

If you hit a decode error, a `pcall` failure, or a framing mismatch outside
what's covered above, please open an issue with a (sanitized, if needed)
`.pcapng`.

> **Testing as root (e.g. inside a container run as `root`):** Wireshark
> silently disables personal Lua plugin loading (both the plugins-folder
> mechanism and `-X lua_script:`) when the effective user is root, as a 
> security precaution, with no warning or error. `tshark -G protocols` 
> simply won't list the SAPIENT dissectors. Run as a non-root user instead.

## Licensing

The dissector code (`plugins/sapient.lua`, `scripts/`) is dual-licensed
under MIT or Apache-2.0, at your option, matching `sapient-rs` and
`sapient-test-harness`. The vendored schema under `proto/` is separately
Crown Copyright, Apache License 2.0, attributed to DSTL -- see
[`proto/LICENCE.txt`](proto/LICENCE.txt).
