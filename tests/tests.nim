import std/[unittest, os]

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
        check readFile(expectedPath) == parseKdlFile(path).pretty()
    else:
      test "Invalid: " & filename:
        expect(KDLError):
          discard parseKdlFile(path)
