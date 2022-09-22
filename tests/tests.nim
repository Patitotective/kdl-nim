import std/[strformat, unittest, os]

import kdl

let testsDir = getAppDir() / "test_cases"

proc escaped(x: string): string = 
  result.addQuoted(x)

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile: continue
    let filename = path.splitPath.tail
    let expectedPath = testsDir / "expected_kdl" / filename

    if fileExists(expectedPath):
      test "Valid: " & filename:
        checkpoint &"- Input: {readFile(path).escaped}\n- Expected: {readFile(expectedPath).escaped}\n- Got: {parseKdlFile(path).pretty().escaped}"
        check readFile(expectedPath) == parseKdlFile(path).pretty()
    else:
      test "Invalid: " & filename:
        checkpoint &"- Input: {readFile(path).escaped}"
        expect(KDLError):
          discard parseKdlFile(path)
