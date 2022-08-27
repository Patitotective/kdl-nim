import std/[strformat, unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail

    if fileExists(testsDir / "expected_kdl" / filename):
      test "Valid: " & filename:
        check validKDL(readFile(path))
    else:
      test "Invalid: " & filename:
        check not validKDL(readFile(path))
