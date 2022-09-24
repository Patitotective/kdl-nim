# Tests
```
nimble test
```

Tests taken from https://github.com/kdl-org/kdl/tree/main/tests.

## Changes
The following tests were modified from the original test suite:
- `hex.kdl`: `node 0xabcdef1234567890` -> `node 0x1234567890abcdef`.
- `hex_int.kdl`: `node 0xABCDEF0123456789abcdef` -> `node 0x1234567890ABCDEF`.

- Tests starting with `_` must be successfully parsed but are not checked with `expected_kdl`.

- New `examples` folder that is identical to https://github.com/kdl-org/kdl/tree/main/examples, all documents inside it must be parsed with no error.
