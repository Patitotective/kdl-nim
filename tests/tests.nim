import std/[unittest, xmlparser, xmltree, json, os]

import kdl, kdl/[schema, query, jik, xik]

let testsDir = getAppDir() / "test_cases"

proc quoted*(x: string): string = result.addQuoted(x)

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

suite "XiK": # Check that kdl-nim can convert XML into KDL forth and back
  for kind, path in walkDir(testsDir / "xik"):
    if kind != pcFile: continue

    let filename = path.splitPath.tail

    test "File: " & filename:
      let data = loadXml(path)
      check $data == $data.toKdl(comments = true).toXml(comments = true)

suite "JiK": # Check that kdl-nim can convert JSON into KDL forth and back
  for kind, path in walkDir(testsDir / "jik"):
    if kind != pcFile: continue

    let filename = path.splitPath.tail

    test "File: " & filename:
      let data = parseFile(path)
      check data == data.toKdl().toJson()
