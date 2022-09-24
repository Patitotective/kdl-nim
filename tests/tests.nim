import std/[unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail
    let expectedPath = testsDir / "expected_kdl" / filename

    if filename[0] == '_':
      test "Ignore: " & filename: # Just check it doesn't error
        discard parseKdlFile(path)

    elif fileExists(expectedPath):
      test "Valid: " & filename:
        check readFile(expectedPath) == parseKdlFile(path).pretty()
    else:
      test "Invalid: " & filename:
        expect(KDLError):
          discard parseKdlFile(path)

suite "examples": # Check that kdl-nim can parse all the documents in the examples folder
  for kind, path in walkDir(testsDir / "examples"):
    if kind != pcFile: continue

    let filename = path.splitPath.tail

    test "Example: " & filename:
      discard parseKdlFile(path)
