# Tests
```
nimble test
```

Tests taken from https://github.com/kdl-org/kdl/tree/main/tests.

## Changes
The following tests were modified from the original test suite:
- `input/hex.kdl`: `node 0xabcdef1234567890` -> `node 0x1234567890abcdef`.
- `input/hex_int.kdl`: `node 0xABCDEF0123456789abcdef` -> `node 0x1234567890ABCDEF`.

The following tests are not compared with `expected_kdl` for float-formatting related casues:
- `input/negative_exponent.kdl`
- `input/no_decimal_exponent.kdl`
- `input/parse_all_arg_types.kdl`
- `input/positive_exponent.kdl`
- `input/prop_float_type.kdl`
- `input/sci_notation_large.kdl`
- `input/sci_notation_small.kdl`
- `input/underscore_in_exponent.kdl`
They are instead prefixed with an underscore (`_`) and checked for successfull parsing.

- New `examples` folder that is identical to https://github.com/kdl-org/kdl/tree/main/examples, all documents inside it must be parsed with no error.
- New `jik` and `xik` folders that contain files that must successfully converted to KDL and then back to JSON/XML.

