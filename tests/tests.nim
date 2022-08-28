import std/[strformat, unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail

    if fileExists(testsDir / "expected_kdl" / filename):
      test "Valid: " & filename:
        check scanKDL(readFile(path)).ok
    else:
      test "Invalid: " & filename:
        check not scanKDL(readFile(path)).ok
