import std/[unittest, xmlparser, xmltree, times, json, os]

import kdl, kdl/[schema, query, jik, xik]

let testsDir = getAppDir() / "test_cases"

proc quoted*(x: string): string = result.addQuoted(x)

proc decodeHook*(a: KdlNode, v: var DateTime) = 
  assert a.args.len == 1
  v = a.args[0].getString.parse("yyyy-MM-dd")

  if "hour" in a.props:
    v.hour = a.props["hour"].getInt
  if "minute" in a.props:
    v.minute = a.props["minute"].getInt
  if "second" in a.props:
    v.second = a.props["second"].getInt
  if "nanosecond" in a.props:
    v.nanosecond = a.props["nanosecond"].getInt
  if "offset" in a.props:
    v.utcOffset = a.props["offset"].get(int)

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
        expect(KdlError):
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

suite "Decoder":
  test "Crate":
    type
      Package = object
        name*, version*: string
        authors*: Option[seq[string]]
        description*, licenseFile*, edition*: Option[string]

      Deps = Table[string, string]

    const
      doc = parseKdl("""
        package {
            name "kdl"
            version "0.0.0"
            description "kat's document language"
            authors "Kat Marchán <kzm@zkat.tech>"
            license-file "LICENSE.md"
            edition "2018"
        }

        dependencies {
            nom "6.0.1"
            thiserror "1.0.22"
        }""")

      package = doc.decode(Package, "package")
      dependencies = doc.decode(Deps, "dependencies")

    check package == Package(name: "kdl", version: "0.0.0", authors: @["Kat Marchán <kzm@zkat.tech>"].some, description: "kat's document language".some, licenseFile: "LICENSE.md".some, edition: "2018".some)
    check dependencies == {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable

  test "Nimble":
    type
      Package = object
        version*, author*, description*, license*: string
        requires*: seq[string]
        obj*: tuple[num: Option[float32]]

    const
      doc = parseKdl("""
        version "0.0.0"
        author "Kat Marchán <kzm@zkat.tech>"
        description "kat's document language"
        license "CC BY-SA 4.0"
        obj num=3.14

        requires "nim >= 0.10.0" "foobar >= 0.1.0" "fizzbuzz >= 1.0"""")
      package = doc.decode(Package)

    check package == Package(version: "0.0.0", author: "Kat Marchán <kzm@zkat.tech>", description: "kat's document language", license: "CC BY-SA 4.0", requires: @["nim >= 0.10.0", "foobar >= 0.1.0", "fizzbuzz >= 1.0"], obj: (num: 3.14f.some))

  test "List":
    type Foo = object
      a*, b*: int

    check parseKdl("node 1 2 3").decode(seq[seq[int]], "node") == @[@[1], @[2], @[3]]
    check parseKdl("node 1 2 3").decode(seq[int], "node") == @[1, 2, 3]

    check parseKdl("node {a 1; b 2}; node {a 3; b 3}").decode(seq[Foo]) == @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    check parseKdl("node 1; node 2").decode(seq[int]) == @[1, 2]

    check parseKdl("node 1 2 3").decode(array[4, int], "node") == [1, 2, 3, 0]
    check parseKdl("node 1 2 3").decode(array[3, int], "node") == [1, 2, 3]
    check parseKdl("node 1 2 3").decode(array[2, int], "node") == [1, 2]
    check parseKdl("node 1 2 3").decode(array[0, int], "node") == []

  test "Options":
    type Person = object
      name*: string
      surname*: Option[string]

    check parseKdl("node \"Nah\"; node \"Pat\"; node").decode(seq[Option[string]]) == @["Nah".some, "Pat".some, string.none]
    check parseKdl("node name=\"Beef\"; node name=\"Pat\" surname=\"ito\"").decode(seq[Person]) == @[Person(name: "Beef", surname: none(string)), Person(name: "Pat", surname: some("ito"))]

  test "SomeTable":
    check parseKdl("key \"value\"; alive true").decode(Table[string, KdlVal]) == {
      "key": "value".initKVal, 
      "alive": true.initKVal
    }.toTable
    check parseKdl("person age=10 name=\"Phil\" {other-name \"Isofruit\"}").decode(Table[string, KdlVal], "person") == {
      "age": 10.initKVal, 
      "name": "Phil".initKVal, 
      "other-name": "Isofruit".initKVal
    }.toTable

    check parseKdl("key \"value\"; alive true").decode(OrderedTable[string, KdlVal]) == {
      "key": "value".initKVal, 
      "alive": true.initKVal
    }.toOrderedTable
    check parseKdl("person age=10 name=\"Phil\" {other-name \"Isofruit\"}").decode(OrderedTable[string, KdlVal], "person") == {
        "age": 10.initKVal, 
        "name": "Phil".initKVal, 
        "other-name": "Isofruit".initKVal
      }.toOrderedTable

  test "Object":
    type
      Person = object
        name*: string
        age*: int

      Game = object
        name*, version*, author*, license*: string

    check parseKdl("person age=20 {name \"Rika\"}").decode(Person, "person") == Person(age: 20, name: "Rika")
    check parseKdl("person age=20 {name \"Rika\"}").decode(tuple[age: int, name: string], "person") == (age: 20, name: "Rika")
    check parseKdl("name \"Mindustry\"; version \"126.2\"; author \"Anuken\"; license \"GNU General Public License v3.0\"").decode(Game) == Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Extra":
    check parseKdl("node 1").decode(int, "node") == 1

    var result: int
    parseKdl("node 1").decode(result, "node")
    check result == 1

    check parseKdl("node true").decode(bool, "node") == true

    check parseKdl("node null \"not null\"").decode(seq[cstring], "node") == @[cstring nil, cstring "not null"]

  test "Custom":
    let date = parseKdl("date \"2000-12-31\" hour=3").decode(DateTime, "date")
    check date.year == 2000
    check date.month == mDec
    check date.hour == 3

  test "Enums":
    type
      Dir = enum
        north, south, west, east
      HoleyDir = enum
        hNorth = 1, hSouth = 3, hWest = 6, hEast = 12

    check parseKdl("dir \"north\" 1").decode(seq[Dir], "dir") == @[north, south]

    when defined(kdlDecoderAllowHoleyEnums):
      check parseKdl("dir 2 3").decode(seq[HoleyDir], "dir") == @[HoleyDir(2), hSouth]
    else:
      expect KdlError:
        discard parseKdl("dir 2 3").decode(seq[HoleyDir], "dir")

  test "Char":
    check parseKdl("rows \"a\" \"b\" \"c\"").decode(seq[char], "rows") == @['a', 'b', 'c']
    check parseKdl("char \"#\"").decode(char, "char") == '#'
