import std/[strformat, unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail

    if fileExists(testsDir / "expected_kdl" / filename):
      test "Valid: " & filename:
        let lexer = scanFile(path)
        check lexer.current == lexer.source.len
    else:
      test "Invalid: " & filename:
        expect(KDLError):
          let lexer = scanFile(path)
