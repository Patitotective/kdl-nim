import std/[xmlparser, unittest, xmltree, json, os]

import kdl
import kdl/[schema, query, jik, xik]

let testsDir = getAppDir() / "test_cases"

suite "spec":
  for kind, path in walkDir(testsDir / "input"):
    if kind != pcFile:
      continue
    let filename = path.splitPath.tail
    let expectedPath = testsDir / "expected_kdl" / filename

    if filename[0] == '_':
      test "Ignore: " & filename:
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

suite "examples":
  for kind, path in walkDir(testsDir / "examples"):
    if kind != pcFile:
      continue

    let filename = path.splitPath.tail

    test "Example: " & filename:
      discard parseKdlFile(path)

suite "XiK":
  for kind, path in walkDir(testsDir / "xik"):
    if kind != pcFile:
      continue

    let filename = path.splitPath.tail

    test "File: " & filename:
      let data = loadXml(path)
      # Here we compare strings otherwise it fails and I can't see why (maybe because they're refs)
      check $data == $data.toKdl(addComments = true).toXml(addComments = true)

suite "JiK":
  for kind, path in walkDir(testsDir / "jik"):
    if kind != pcFile:
      continue

    let filename = path.splitPath.tail

    test "File: " & filename:
      let data = parseFile(path)
      check data == data.toKdl().toJson()

suite "Other":
  test "Nodes":
    check toKdlArgs("abc", 123, 3.14, true, nil) ==
      ["abc".initKVal, 123.initKVal, 3.14.initKVal, true.initKVal, initKNull()]
    check toKdlProps({"a": "abc", "b": 123, "c": 3.14, "d": false, "e": nil}) == {
      "a": "abc".initKVal,
      "b": 123.initKVal,
      "c": 3.14.initKVal,
      "d": false.initKVal,
      "e": initKNull(),
    }.toTable

  test "Escaping":
    check ($toKdlVal("'")).parseKdl[0] == initKNode("'")
