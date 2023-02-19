import std/[xmlparser, unittest, xmltree, json, os]

import kdl
import kdl/[schema, query, jik, xik]

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
      test "Valid: " & filename & " [Stream]":
        check readFile(expectedPath) == parseKdlFileStream(path).pretty()
    else:
      test "Invalid: " & filename:
        expect(KdlError):
          discard parseKdlFile(path)
      test "Invalid: " & filename & " [Stream]":
        expect(KdlError):
          discard parseKdlFileStream(path)

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

suite "Other":
  test "Nodes":
    check toKdlArgs("abc", 123, 3.14, true, nil) == ["abc".initKVal, 123.initKVal, 3.14.initKVal, true.initKVal, initKNull()]
    check toKdlProps({"a": "abc", "b": 123, "c": 3.14, "d": false, "e": nil}) == {"a": "abc".initKVal, "b": 123.initKVal, "c": 3.14.initKVal, "d": false.initKVal, "e": initKNull()}.toTable
