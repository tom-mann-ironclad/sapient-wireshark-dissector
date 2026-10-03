# Test fixtures

`registration_v2.sapient-framed.bin` is real SAPIENT wire bytes: a genuine
`sapient-test-harness` fixture
(`crates/sapient-conformance-core/tests/fixtures/True/Registration.FullMesssage.Bearing.json`),
decoded and re-encoded with that project's own `prost`-generated encoder,
then framed exactly as the wire format requires -- a 4-byte little-endian
length prefix followed by the protobuf payload. It is not hand-crafted, so
a passing decode is evidence the dissector handles real encoder output, not
just bytes shaped to make the test pass.

Regenerate it (e.g. after a schema change) from a `sapient-test-harness`
checkout:

```bash
cat > /tmp/pcapgen.rs <<'EOF'
use std::fs;
use prost::Message;
use sapient_conformance_core::fixture_json::{decode_sapient_message_json, sapient_message_descriptor};

fn main() {
    let json = fs::read_to_string(std::env::args().nth(1).unwrap()).unwrap();
    let descriptor = sapient_message_descriptor();
    let message = decode_sapient_message_json(&json, &descriptor).unwrap();
    let payload = message.encode_to_vec();
    let mut framed = (payload.len() as u32).to_le_bytes().to_vec();
    framed.extend_from_slice(&payload);
    fs::write(std::env::args().nth(2).unwrap(), &framed).unwrap();
}
EOF
# compile/run against sapient-conformance-core, pointed at the fixture above,
# writing to tests/fixtures/registration_v2.sapient-framed.bin
```

See `tests/decode_smoke_test.sh` for how CI uses this fixture.
