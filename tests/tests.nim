import std/[strformat, strutils, unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail
    let expectedPath = testsDir / "expected_kdl" / filename

    if fileExists(expectedPath):
      test "Valid: " & filename:
        # checkpoint &"Expected: {readFile(expectedPath).escape} --- Got: {parseKdlFile(path).pretty().escape}"
        check readFile(expectedPath) == parseKdlFile(path).pretty()
    else:
      test "Invalid: " & filename:
        expect(KDLError):
          discard parseKdlFile(path)
