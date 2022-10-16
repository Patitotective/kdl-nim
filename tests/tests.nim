import std/[strformat, xmlparser, unittest, strutils, xmltree, times, json, os]

import kdl
import kdl/[schema, query, jik, xik]
import kdl/utils except check

type
  MyObjKind = enum
    moInt, moString
  
  MyObj = object
    case kind*: MyObjKind
    of moInt:
      intV*: int
    of moString:
      stringV*: string

    case kind2*: MyObjKind
    of moInt:
      intV2*: int
    of moString:
      stringV2*: string

  MyObj2 = object
    id*: int
    name*: string

  MyObj3 = object
    id*: int
    name*: string

  MyObj4 = object
    kind*: string
    list*: seq[int]

  MyEnum = enum
    meNorth, meSouth, meWest, meEast

proc `==`(a, b: MyObj): bool = 
  assert a.kind == b.kind
  assert a.kind2 == b.kind2

  result = 
    case a.kind
    of moInt:
      a.intV == b.intV
    of moString:
      a.stringV == b.stringV

  result = 
    case a.kind2
    of moInt:
      result and a.intV2 == b.intV2
    of moString:
      result and a.stringV2 == b.stringV2


proc newHook*(v: var DateTime) = 
  v = dateTime(2000, mMar, 30)

proc newHook*(v: var MyObj2) = 
  v.id = 5

proc postHook*(v: var MyObj3) = 
  inc v.id

proc enumHook*(a: string, v: var MyEnum) = 
  case a.toLowerAscii
  of "north":
    v = meNorth
  of "south":
    v = meSouth
  of "west":
    v = meWest
  of "east":
    v = meEast
  else:
    raise newException(ValueError, &"invalid enum value {a} for {$typeof(v)}")

proc enumHook*(a: int, v: var MyEnum) = 
  case a
  of 0xbeef:
    v = meNorth
  of 0xcafe:
    v = meSouth
  of 0xface:
    v = meWest
  of 0xdead:
    v = meEast
  else:
    raise newException(ValueError, &"invalid enum value {a} for {$typeof(v)}")

proc renameHook*(_: typedesc[MyObj4], fieldName: var string) = 
  fieldName = 
    case fieldName
    of "type":
      "kind"
    of "array":
      "list"
    else:
      fieldName

proc decodeHook*(a: KdlVal, v: var DateTime) = 
  assert a.isString
  v = a.getString.parse("yyyy-MM-dd")

proc decodeHook*(a: KdlNode, v: var DateTime) = 
  case a.args.len
  of 6: # year month day hour minute second
    v = dateTime(
      a.args[0].decode(int), 
      a.args[1].decode(Month), 
      a.args[2].decode(MonthdayRange), 
      a.args[3].decode(HourRange), 
      a.args[4].decode(MinuteRange), 
      a.args[5].decode(SecondRange)
    )
  of 3: # year month day
    v = dateTime(
      a.args[0].decode(int), 
      a.args[1].decode(Month), 
      a.args[2].decode(MonthdayRange), 
    )
  of 1: # yyyy-MM-dd 
    a.args[0].decode(v)
  else:
    doAssert a.args.len in {1, 3, 6}

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

proc decodeHook*(a: KdlDoc, v: var DateTime) = 
  if a.len == 0: return

  var
    year: int
    month: Month
    day: MonthdayRange = 1
    hour: HourRange
    minute: MinuteRange
    second: SecondRange
    nanosecond: NanosecondRange

  for node in a:
    if node.name.eqIdent "year":
      node.decode(year)
    elif node.name.eqIdent "month":
      node.decode(month)
    elif node.name.eqIdent "day":
      node.decode(day)
    elif node.name.eqIdent "hour":
      node.decode(hour)
    elif node.name.eqIdent "minute":
      node.decode(minute)
    elif node.name.eqIdent "second":
      node.decode(second)
    elif node.name.eqIdent "nanosecond":
      node.decode(nanosecond)

  v = dateTime(year, month, day, hour, minute, second, nanosecond)

proc encodeHook*(a: DateTime, v: var KdlDoc) = 
  v = @[
    initKNode("year", args = @[encode(a.year, KdlVal)]), 
    initKNode("month", args = @[encode(a.month, KdlVal)]), 
    initKNode("day", args = @[encode(a.monthday, KdlVal)]), 
    initKNode("hour", args = @[encode(a.hour, KdlVal)]), 
    initKNode("minute", args = @[encode(a.minute, KdlVal)]), 
    initKNode("second", args = @[encode(a.second, KdlVal)]), 
    initKNode("nanosecond", args = @[encode(a.nanosecond, KdlVal)]), 
  ]

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

  test "Seqs and arrays":
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

  test "Tables":
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

  test "Objects":
    type
      Person = object
        name*: string
        age*: int

      Game = object
        name*, version*, author*, license*: string

    check parseKdl("person age=20 {name \"Rika\"}").decode(Person, "person") == Person(age: 20, name: "Rika")
    check parseKdl("person age=20 {name \"Rika\"}").decode(tuple[age: int, name: string], "person") == (age: 20, name: "Rika")
    check parseKdl("name \"Mindustry\"; version \"126.2\"; author \"Anuken\"; license \"GNU General Public License v3.0\"").decode(Game) == Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Object variants":
    check parseKdl("""
    node kind="moString" stringV="Hello"
    node kind="moInt" intV=12
    node kind="moString" stringV="Beef" kind2="moInt" intV2=0xbeef
    """).decode(seq[MyObj]) == @[MyObj(kind: moString, stringV: "Hello"), MyObj(kind: moInt, intV: 12), MyObj(kind: moString, stringV: "Beef", kind2: moInt, intV2: 0xbeef)]

    check parseKdl("""
    kind "moString"
    stringV "World"
    """).decode(MyObj) == MyObj(kind: moString, stringV: "World")

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

  test "Chars":
    check parseKdl("rows \"a\" \"b\" \"c\"").decode(seq[char], "rows") == @['a', 'b', 'c']
    check parseKdl("char \"#\"").decode(char, "char") == '#'

  test "Extra":
    check parseKdl("node 1").decode(int, "node") == 1

    var result: int
    parseKdl("node 1").decode(result, "node")
    check result == 1

    check parseKdl("node true").decode(bool, "node") == true

    check parseKdl("node null \"not null\"").decode(seq[cstring], "node") == @[cstring nil, cstring "not null"]

  test "Custom":
    check parseKdl("""
    year 2022
    month 10 // or "October"
    day 15
    hour 12
    minute 10
    """).decode(DateTime) == dateTime(2022, mOct, 15, 12, 10)

    check parseKdl("date 2022 \"October\" 15 12 04 00").decode(DateTime, "date") == dateTime(2022, mOct, 15, 12, 04)

    check parseKdl("author birthday=\"2000-10-15\" name=\"Nobody\"")[0]["birthday"].decode(DateTime) == dateTime(2000, mOct, 15)

  test "newHook":
    check parseKdl("").decode(DateTime) == dateTime(2000, mMar, 30)
    check parseKdl("name \"otoboke\"").decode(MyObj2) == MyObj2(id: 5, name: "otoboke")

  test "postHook":
    check parseKdl("id 4").decode(MyObj3) == MyObj3(id: 5)

  test "enumHook":
    check parseKdl("""
    node "north" "south" "west" "east"
    """).decode(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

    check parseKdl("""
    node 0xbeef 0xcafe 0xface 0xdead
    """).decode(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

  test "renameHook":
    check parseKdl("""
    type "string"
    array 1 2 3
    """).decode(MyObj4) == MyObj4(kind: "string", list: @[1, 2, 3])

template encodeDecodes(x): untyped = 
  x.encode().decode(typeof x) == x

template encodeDecodes(x: untyped, name: string): untyped = 
  x.encode(name).decode(typeof x) == x

suite "Encoder":
  test "Crate":
    type
      Package = object
        name*, version*: string
        authors*: Option[seq[string]]
        description*, licenseFile*, edition*: Option[string]

    check encodeDecodes Package(name: "kdl", version: "0.0.0", authors: @["Kat Marchán <kzm@zkat.tech>"].some, description: "kat's document language".some, licenseFile: "LICENSE.md".some, edition: "2018".some)
    check encodeDecodes {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable

  test "Nimble":
    type
      Package = object
        version*, author*, description*, license*: string
        requires*: seq[string]
        obj*: tuple[num: Option[float32]]

    check encodeDecodes Package(version: "0.0.0", author: "Kat Marchán <kzm@zkat.tech>", description: "kat's document language", license: "CC BY-SA 4.0", requires: @["nim >= 0.10.0", "foobar >= 0.1.0", "fizzbuzz >= 1.0"], obj: (num: 3.14f.some))

  test "Seqs and arrays":
    type Foo = object
      a*, b*: int

    check encodeDecodes @[@[1], @[2], @[3]]
    check encodeDecodes @[1, 2, 3]

    check encodeDecodes @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    check encodeDecodes @[1, 2]

    check encodeDecodes [1, 2, 3, 0]
    check encodeDecodes [1, 2, 3]
    check encodeDecodes [1, 2]
    check encodeDecodes array[0, int].default

  test "Options":
    type Person = object
      name*: string
      surname*: Option[string]

    check encodeDecodes @["Nah".some, "Pat".some, string.none]
    check encodeDecodes @[Person(name: "Beef", surname: none(string)), Person(name: "Pat", surname: some("ito"))]

  test "Tables":
    check encodeDecodes {
      "key": "value".initKVal, 
      "alive": true.initKVal
    }.toTable
    check encodeDecodes {
      "age": 10.initKVal, 
      "name": "Phil".initKVal, 
      "other-name": "Isofruit".initKVal
    }.toTable

    check encodeDecodes {
      "key": "value".initKVal, 
      "alive": true.initKVal
    }.toOrderedTable
    check encodeDecodes {
        "age": 10.initKVal, 
        "name": "Phil".initKVal, 
        "other-name": "Isofruit".initKVal
      }.toOrderedTable

  test "Objects":
    type
      Person = object
        name*: string
        age*: int

      Game = object
        name*, version*, author*, license*: string

    check encodeDecodes Person(age: 20, name: "Rika")
    check encodeDecodes (age: 20, name: "Rika")
    check encodeDecodes Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Object variants":
    check encodeDecodes @[MyObj(kind: moString, stringV: "Hello"), MyObj(kind: moInt, intV: 12), MyObj(kind: moString, stringV: "Beef", kind2: moInt, intV2: 0xbeef)]

    check encodeDecodes MyObj(kind: moString, stringV: "World")

  test "Enums":
    type
      Dir = enum
        north, south, west, east
      HoleyDir = enum
        hNorth = 1, hSouth = 3, hWest = 6, hEast = 12

    check encodeDecodes @[north, south]

    when defined(kdlDecoderAllowHoleyEnums):
      check encodeDecodes @[HoleyDir(2), hSouth]

  test "Chars":
    check encodeDecodes @['a', 'b', 'c']
    check encodeDecodes('#', "node")

  test "Extra":
    check encodeDecodes(1, "node")

    check encodeDecodes(true, "node")

    check encodeDecodes @[cstring nil, cstring "not null"]

  test "Custom":
    check encodeDecodes dateTime(2022, mOct, 15, 12, 10)

    check encodeDecodes dateTime(2022, mOct, 15, 12, 04)

    check encodeDecodes dateTime(2000, mOct, 15)
