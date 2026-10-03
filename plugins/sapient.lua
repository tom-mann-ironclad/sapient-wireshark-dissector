-- SAPIENT / BSI Flex 335 Wireshark dissector.
--
-- SAPIENT's wire framing is a 4-byte LITTLE-endian length prefix followed by
-- that many bytes of protobuf payload, repeated for the life of the TCP
-- connection: [len][message][len][message]... (see sapient-rs's own framing
-- helpers, or sapient-test-harness's crates/sapient-session/src/framing.rs).
-- This is the one detail that differs from Wireshark's own wiki example
-- (wiki.wireshark.org/Protobuf), which demonstrates the same length-prefixed
-- shape but with a big-endian length -- that example is illustrative, not a
-- fixed requirement of Wireshark's protobuf dissector, so this file is that
-- same pattern with the prefix read as little-endian and the two SAPIENT
-- message types wired in. Everything else (actually decoding the protobuf
-- payload against a message type) is handled entirely by Wireshark's own
-- built-in "protobuf" dissector; this file does no protobuf parsing itself.
--
-- Setup (see README.md for the full walkthrough):
--   1. Edit -> Preferences -> Protocols -> ProtoBuf -> Protobuf search paths:
--      add this repo's `proto/` directory, and enable "Load all files".
--   2. Place this file in Wireshark's personal or global Lua plugins folder.
--   3. On a SAPIENT TCP stream, right-click -> Decode As -> set the
--      "Current" protocol to "SAPIENT (BSI Flex 335 v2.0)" (or v1.0).

do
    local protobuf_dissector = Dissector.get("protobuf")

    -- `name` becomes the dissector's short protocol name (shown in the
    -- "Protocol" column and in the Decode As list); `msgtype` is the fully
    -- qualified root message name from the .proto `package` declaration,
    -- which must match what's loadable from the configured search paths.
    local function create_sapient_dissector(name, desc, msgtype)
        local proto = Proto(name, desc)
        local f_length = ProtoField.uint32(name .. ".length", "Length", base.DEC)
        proto.fields = { f_length }

        proto.dissector = function(tvb, pinfo, tree)
            local subtree = tree:add(proto, tvb())
            pinfo.columns.protocol:set(name)

            local offset = 0
            local remaining_len = tvb:len()
            while remaining_len > 0 do
                if remaining_len < 4 then
                    pinfo.desegment_offset = offset
                    pinfo.desegment_len = DESEGMENT_ONE_MORE_SEGMENT
                    return
                end

                -- The one departure from Wireshark's own wiki example:
                -- SAPIENT's length prefix is little-endian.
                local data_len = tvb(offset, 4):le_uint()

                if remaining_len - 4 < data_len then
                    pinfo.desegment_offset = offset
                    pinfo.desegment_len = data_len - (remaining_len - 4)
                    return
                end
                subtree:add_le(f_length, tvb(offset, 4))

                pinfo.private["pb_msg_type"] = "message," .. msgtype
                pcall(
                    Dissector.call,
                    protobuf_dissector,
                    tvb(offset + 4, data_len):tvb(),
                    pinfo,
                    subtree
                )

                offset = offset + 4 + data_len
                remaining_len = remaining_len - 4 - data_len
            end
        end

        -- Registered for "Decode As" only, not bound to a default port --
        -- SAPIENT doesn't mandate one, and the DMM/ASM roles can listen on
        -- whatever the deployment configures.
        DissectorTable.get("tcp.port"):add_for_decode_as(proto)
        return proto
    end

    create_sapient_dissector(
        "SAPIENT_V2",
        "SAPIENT (BSI Flex 335 v2.0)",
        "sapient_msg.bsi_flex_335_v2_0.SapientMessage"
    )
    create_sapient_dissector(
        "SAPIENT_V1",
        "SAPIENT (BSI Flex 335 v1.0)",
        "sapient_msg.bsi_flex_335_v1_0.SapientMessage"
    )
end
