# Tests
```
nimble test
```

Tests taken from https://github.com/kdl-org/kdl/tree/main/tests.

## Modified tests
The following tests were modified from the original test suite.
- `hex.kdl`: `node 0xabcdef1234567890` -> `node 0x1234567890abcdef`.
- `hex_int.kdl`: `node 0xABCDEF0123456789abcdef` -> `node 0x1234567890ABCDEF`.
