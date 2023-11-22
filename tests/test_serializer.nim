import std/[strformat, strutils, unittest, options, tables, strtabs, times, sets]
import kdl
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

  MyEnum = enum
    meNorth, meSouth, meWest, meEast

  AllObj = object
    id*: int64
    id2*: uint32
    name*: (string, bool)
    subrange*: range[0f..1f]
    node*: KdlNode
    val*: KdlVal
    doc*: KdlDoc
    items*: seq[char]
    items2*: array[2, byte]
    items3*: set[char]
    items4*: HashSet[string]
    items5*: OrderedSet[string]
    obj*: MyObj
    table*: Table[string, char]
    table2*: OrderedTable[string, int16]
    table3*: StringTableRef
    option*: Option[MyEnum]

  MyObj2 = object
    id*: int

  MyObj4 = object
    kind*: string
    list*: seq[int]

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

proc initHookKdl*(v: var DateTime) =
  v = dateTime(2000, mMar, 30)

proc enumHookKdl*(a: string, v: var MyEnum) =
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
    v = parseEnum[MyEnum](a)

proc enumHookKdl*(a: int, v: var MyEnum) =
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

proc renameHookKdl*(_: typedesc[MyObj4 or MyObj], fieldName: var string) =
  fieldName =
    case fieldName
    of "type":
      "kind"
    of "type2":
      "kind2"
    of "array":
      "list"
    else:
      fieldName

proc decodeKdl*(a: KdlVal, v: var DateTime) =
  decodeInitKdl(v)
  assert a.isString
  v = a.getString.parse("yyyy-MM-dd")

proc decodeKdl*(a: KdlNode, v: var DateTime) =
  decodeInitKdl(v)
  case a.args.len
  of 6: # year month day hour minute second
    v = dateTime(
      a.args[0].decodeKdl(int),
      a.args[1].decodeKdl(Month),
      a.args[2].decodeKdl(MonthdayRange),
      a.args[3].decodeKdl(HourRange),
      a.args[4].decodeKdl(MinuteRange),
      a.args[5].decodeKdl(SecondRange)
    )
  of 3: # year month day
    v = dateTime(
      a.args[0].decodeKdl(int),
      a.args[1].decodeKdl(Month),
      a.args[2].decodeKdl(MonthdayRange),
    )
  of 1: # yyyy-MM-dd
    a.args[0].decodeKdl(v)
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

proc decodeKdl*(a: KdlDoc, v: var DateTime) =
  decodeInitKdl(v)
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
    assert node.args.len == 1
    if node.name.eqIdent "year":
      node.args[0].decodeKdl(year)
    elif node.name.eqIdent "month":
      node.args[0].decodeKdl(month)
    elif node.name.eqIdent "day":
      node.args[0].decodeKdl(day)
    elif node.name.eqIdent "hour":
      node.args[0].decodeKdl(hour)
    elif node.name.eqIdent "minute":
      node.args[0].decodeKdl(minute)
    elif node.name.eqIdent "second":
      node.args[0].decodeKdl(second)
    elif node.name.eqIdent "nanosecond":
      node.args[0].decodeKdl(nanosecond)

  v = dateTime(year, month, day, hour, minute, second, nanosecond)

proc encodeKdl*(a: DateTime, v: var KdlDoc) =
  v = @[
    initKNode("year", args = @[encodeKdlVal(a.year)]),
    initKNode("month", args = @[encodeKdlVal(a.month)]),
    initKNode("day", args = @[encodeKdlVal(a.monthday)]),
    initKNode("hour", args = @[encodeKdlVal(a.hour)]),
    initKNode("minute", args = @[encodeKdlVal(a.minute)]),
    initKNode("second", args = @[encodeKdlVal(a.second)]),
    initKNode("nanosecond", args = @[encodeKdlVal(a.nanosecond)]),
  ]

proc initHookKdl*(v: var MyObj2) = v.id = 100

proc postHookKdl*(v: var MyObj2) = inc v.id

# Otherwise the comparision fails
proc `==`(a, b: StringTableRef): bool =
  if a.isNil and b.isNil: true
  elif a.isNil xor b.isNil: false
  else: a[] == b[]

template encodeDecodesDoc(x): untyped =
  let a = x
  when x is ref:
    a.encodeKdlDoc().decodeKdl(typeof a)[] == a[]
  else:
    a.encodeKdlDoc().decodeKdl(typeof a) == a

template encodeDecodesNode(x: untyped, name: string): untyped =
  let a = x
  when a is ref:
    a.encodeKdlNode(name).decodeKdl(typeof a)[] == a[]
  else:
    a.encodeKdlNode(name).decodeKdl(typeof a) == a

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
            description "kats document language"
            authors "Kat Marchán <kzm@zkat.tech>"
            license-file "LICENSE.md"
            edition "2018"
        }

        dependencies {
            nom "6.0.1"
            thiserror "1.0.22"
        }""")

      package = doc.decodeKdl(Package, "package")
      dependencies = doc.decodeKdl(Deps, "dependencies")

    check package == Package(name: "kdl", version: "0.0.0", authors: @["Kat Marchán <kzm@zkat.tech>"].some, description: "kats document language".some, licenseFile: "LICENSE.md".some, edition: "2018".some)
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
        description "kats document language"
        license "CC BY-SA 4.0"
        obj num=3.14

        requires "nim >= 0.10.0" "foobar >= 0.1.0" "fizzbuzz >= 1.0"""")
      package = doc.decodeKdl(Package)

    check package == Package(version: "0.0.0", author: "Kat Marchán <kzm@zkat.tech>", description: "kats document language", license: "CC BY-SA 4.0", requires: @["nim >= 0.10.0", "foobar >= 0.1.0", "fizzbuzz >= 1.0"], obj: (num: 3.14f.some))

  test "Seq":
    type Foo = object
      a*, b*: int

    check parseKdl("node 1 2 3").decodeKdl(seq[seq[int]], "node") == @[@[1], @[2], @[3]]
    check parseKdl("node 1 2 3").decodeKdl(seq[int], "node") == @[1, 2, 3]

    check parseKdl("node {a 1; b 2}; node {a 3; b 3}").decodeKdl(seq[Foo]) == @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    check parseKdl("node 1; node 2").decodeKdl(seq[int]) == @[1, 2]

  test "Array":
    type Foo = object
      a*, b*: int

    check parseKdl("node 1 2 3").decodeKdl(array[3, array[1, int]], "node") == [[1], [2], [3]]
    check parseKdl("node 1 2").decodeKdl(array[2, int], "node") == [1, 2]
    check parseKdl("node 1 2 3").decodeKdl(array[1, int], "node") == [1]
    check parseKdl("node 1 2 3").decodeKdl(array[0, int], "node") == []

    check parseKdl("node {a 1; b 2}; node {a 3; b 3}").decodeKdl(array[2, Foo]) == @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    check parseKdl("node 1; node 2").decodeKdl(array[2, int]) == @[1, 2]

  test "Option":
    type Person = object
      name*: string
      surname*: Option[string]

    check parseKdl("node \"Nah\"; node \"Pat\"; node").decodeKdl(seq[Option[string]]) == @["Nah".some, "Pat".some, string.none]
    check parseKdl("node name=\"Beef\"; node name=\"Pat\" surname=\"ito\"").decodeKdl(seq[Person]) == @[Person(name: "Beef", surname: none(string)), Person(name: "Pat", surname: some("ito"))]

  test "Tables":
    check parseKdl("key \"value\"; alive true").decodeKdl(Table[string, KdlVal]) == {
      "key": "value".initKVal,
      "alive": true.initKVal
    }.toTable
    check parseKdl("person age=10 name=\"Phil\" {other-name \"Isofruit\"}").decodeKdl(Table[string, KdlVal], "person") == {
      "age": 10.initKVal,
      "name": "Phil".initKVal,
      "other-name": "Isofruit".initKVal
    }.toTable

    check parseKdl("key \"value\"; alive true").decodeKdl(OrderedTable[string, KdlVal]) == {
      "key": "value".initKVal,
      "alive": true.initKVal
    }.toOrderedTable
    check parseKdl("person age=10 name=\"Phil\" {other-name \"Isofruit\"}").decodeKdl(OrderedTable[string, KdlVal], "person") == {
        "age": 10.initKVal,
        "name": "Phil".initKVal,
        "other-name": "Isofruit".initKVal
      }.toOrderedTable

  test "Object & Tuple":
    type
      Person = object
        name*: string
        age*: int

      Game = object
        name*, version*, author*, license*: string

    check parseKdl("person age=20 {name \"Rika\"}").decodeKdl(Person, "person") == Person(age: 20, name: "Rika")
    check parseKdl("person age=20 {name \"Rika\"}").decodeKdl(tuple[age: int, name: string], "person") == (age: 20, name: "Rika")
    check parseKdl("name \"Mindustry\"; version \"126.2\"; author \"Anuken\"; license \"GNU General Public License v3.0\"").decodeKdl(Game) == Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Ref Object":
    type
      Person = ref object
        name*: string
        age*: int

      Game = ref object
        name*, version*, author*, license*: string

      RefObj = ref object
        next*: RefObj

    proc `==`(a, b: RefObj): bool =
      if a.isNil and b.isNil:
        true
      elif not a.isNil and not b.isNil:
        a.next == b.next
      else:
        false

    check parseKdl("person age=20 {name \"Rika\"}").decodeKdl(Person, "person")[] == Person(age: 20, name: "Rika")[]
    check parseKdl("name \"Mindustry\"; version \"126.2\"; author \"Anuken\"; license \"GNU General Public License v3.0\"").decodeKdl(Game)[] == Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")[]
    check parseKdl("refobj { next next=null }").decodeKdl(RefObj, "refobj")  == RefObj(next: RefObj(next: nil))

  test "Object Variant":
    check parseKdl("""
    node kind="moString" stringV="Hello"
    node kind="moInt" intV=12
    node kind="moString" stringV="Beef" kind2="moInt" intV2=0xbeef
    """).decodeKdl(seq[MyObj]) == @[MyObj(kind: moString, stringV: "Hello"), MyObj(kind: moInt, intV: 12), MyObj(kind: moString, stringV: "Beef", kind2: moInt, intV2: 0xbeef)]

    check parseKdl("""
    kind "moString"
    stringV "World"
    """).decodeKdl(MyObj) == MyObj(kind: moString, stringV: "World")

  test "Enum":
    type
      Dir = enum
        north, south, west, east
      HoleyDir = enum
        hNorth = 1, hSouth = 3, hWest = 6, hEast = 12

    check parseKdl("dir \"north\" 1").decodeKdl(seq[Dir], "dir") == @[north, south]

    when defined(kdlDecoderAllowHoleyEnums):
      check parseKdl("dir 2 3").decodeKdl(seq[HoleyDir], "dir") == @[HoleyDir(2), hSouth]
    else:
      expect KdlError:
        discard parseKdl("dir 2 3").decodeKdl(seq[HoleyDir], "dir")

  test "Char":
    check parseKdl("rows \"a\" \"b\" \"c\"").decodeKdl(seq[char], "rows") == @['a', 'b', 'c']
    check parseKdl("char \"#\"").decodeKdl(char, "char") == '#'
    expect KdlError:
      discard parseKdl("char \"abc\"").decodeKdl(char, "char")

  # test "Cstring":
  #   check parseKdl("node null \"not null\"").decodeKdl(seq[cstring], "node") == @[cstring nil, cstring "not null"]

  test "Extra":
    check parseKdl("node 1").decodeKdl(int, "node") == 1

    var result: int
    parseKdl("node 1").decodeKdl(result, "node")
    check result == 1

    check parseKdl("node true").decodeKdl(bool, "node") == true

  test "All":
    let obj = AllObj(
      id: 2000i64, id2: 20000u32,
      name: ("ai", true), subrange: 0.5f,
      node: initKNode("node"), val: initKVal(true),
      doc: @[initKNode("first"), initKNode("second")],
      items: @['o', 'v', 'e'], items2: [114, 108],
      items3: {'o', 'r', 'd'}, items4: ["ognmoma", "vole"].toHashSet,
      items5: ["rame", "kisu"].toOrderedSet,
      obj: MyObj(kind: moString, stringV: "mclitneen", kind2: moInt, intV2: 0xdead),
      table: {"mlicb": 'F'}.toTable, table2: {"hakumuse": 500i16}.toOrderedTable,
      table3: {"a": "b", "c": "d"}.newStringTable,
      option: meWest.some
    )

    let doc = parseKdl("""
id 2000; id2 20000
name "ai" true; subrange 0.5
node; val true
doc { first; second }
items "o" "v" "e"; items2 114 108
items3 "o" "r" "d"; items4 "ognmoma" "vole"
items5 "rame" "kisu"
obj stringV="mclitneen" kind="moString" kind2="moInt" intV2=0xdead
table mlicb="F"; table2 hakumuse=500; table3 a="b" c="d"
option "west"
    """)

    let node = parseKdl("""
all id=2000 id2=20000 subrange=0.5 \
val=true option="west" {
name "ai" true
node; doc { first; second }
items "o" "v" "e"; items2 114 108
items3 "o" "r" "d"; items4 "ognmoma" "vole"
items5 "rame" "kisu"
obj kind="moString" stringV="mclitneen" kind2="moInt" intV2=0xdead
table mlicb="F"; table2 hakumuse=500; table3 a="b" c="d"
}
    """)[0]

    check doc.decodeKdl(AllObj) == obj
    check node.decodeKdl(AllObj) == obj

  test "custom decodeKdl":
    check parseKdl("""
    year 2022
    month 10 // or "October"
    day 15
    hour 12
    minute 10
    """).decodeKdl(DateTime) == dateTime(2022, mOct, 15, 12, 10)

    check parseKdl("date 2022 \"October\" 15 12 04 00").decodeKdl(DateTime, "date") == dateTime(2022, mOct, 15, 12, 04)

    check parseKdl("author birthday=\"2000-10-15\" name=\"Nobody\"")[0]["birthday"].decodeKdl(DateTime) == dateTime(2000, mOct, 15)

  test "decodeInitKdl":
    check parseKdl("").decodeKdl(DateTime) == dateTime(2000, mMar, 30)
    check parseKdl("").decodeKdl(MyObj2) == MyObj2(id: 101) # init 100 + post 1

  test "decodePostKdl":
    check parseKdl("- id=4").decodeKdl(MyObj2, "-") == MyObj2(id: 5)

  test "decodeEnumKdl":
    check parseKdl("""
    node "north" "south" "west" "east"
    """).decodeKdl(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

    check parseKdl("""
    node 0xbeef 0xcafe 0xface 0xdead
    """).decodeKdl(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

  test "decodeRenameKdl":
    check parseKdl("""
    type "string"
    array 1 2 3
    """).decodeKdl(MyObj4) == MyObj4(kind: "string", list: @[1, 2, 3])

    check parseKdl("""
    node type="string" {
      array 1 2 3
    }
    """).decodeKdl(MyObj4, "node") == MyObj4(kind: "string", list: @[1, 2, 3])

    check parseKdl("""
    type "moString"
    stringV "hello"
    type2 "moInt"
    intV2 0xbeef
    """).decodeKdl(MyObj) == MyObj(kind: moString, stringV: "hello", kind2: moInt, intV2: 0xbeef)

    check parseKdl("""
    node type="moString" type2="moInt" {
      stringV "bye"
      intV2 0xdead
    }
    """).decodeKdl(MyObj, "node") == MyObj(kind: moString, stringV: "bye", kind2: moInt, intV2: 0xdead)


suite "Encoder":
  test "Crate":
    type
      Package = object
        name*, version*: string
        authors*: Option[seq[string]]
        description*, licenseFile*, edition*: Option[string]

    check encodeDecodesDoc Package(name: "kdl", version: "0.0.0", authors: @["Kat Marchán <kzm@zkat.tech>"].some, description: "kat's document language".some, licenseFile: "LICENSE.md".some, edition: "2018".some)
    check encodeDecodesDoc {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable

  test "Nimble":
    type
      Package = object
        version*, author*, description*, license*: string
        requires*: seq[string]
        obj*: tuple[num: Option[float32]]

    check encodeDecodesDoc Package(version: "0.0.0", author: "Kat Marchán <kzm@zkat.tech>", description: "kat's document language", license: "CC BY-SA 4.0", requires: @["nim >= 0.10.0", "foobar >= 0.1.0", "fizzbuzz >= 1.0"], obj: (num: 3.14f.some))

  test "Seqs and arrays":
    type Foo = object
      a*, b*: int

    check encodeDecodesDoc @[@[1], @[2], @[3]]
    check encodeDecodesDoc @[1, 2, 3]

    check encodeDecodesDoc @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    check encodeDecodesDoc @[1, 2]

    check encodeDecodesDoc [1, 2, 3, 0]
    check encodeDecodesDoc [1, 2, 3]
    check encodeDecodesDoc [1, 2]
    check encodeDecodesDoc array[0, int].default

  test "Options":
    type Person = object
      name*: string
      surname*: Option[string]

    check encodeDecodesDoc @["Nah".some, "Pat".some, string.none]
    check encodeDecodesDoc @[Person(name: "Beef", surname: none(string)), Person(name: "Pat", surname: some("ito"))]

  test "Tables":
    check encodeDecodesDoc {
      "key": "value".initKVal,
      "alive": true.initKVal
    }.toTable
    check encodeDecodesDoc {
      "age": 10.initKVal,
      "name": "Phil".initKVal,
      "other-name": "Isofruit".initKVal
    }.toTable

    check encodeDecodesDoc {
      "key": "value".initKVal,
      "alive": true.initKVal
    }.toOrderedTable
    check encodeDecodesDoc {
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

    check encodeDecodesDoc Person(age: 20, name: "Rika")
    check encodeDecodesDoc (age: 20, name: "Rika")
    check encodeDecodesDoc Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Refs":
    type
      Person = ref object
        name*: string
        age*: int

      Game = ref object
        name*, version*, author*, license*: string

    check encodeDecodesDoc Person(age: 20, name: "Rika")
    check encodeDecodesDoc (age: 20, name: "Rika")
    check encodeDecodesDoc Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  test "Object variants":
    check encodeDecodesDoc @[MyObj(kind: moString, stringV: "Hello"), MyObj(kind: moInt, intV: 12), MyObj(kind: moString, stringV: "Beef", kind2: moInt, intV2: 0xbeef)]

    check encodeDecodesDoc MyObj(kind: moString, stringV: "World")

  test "Enums":
    type
      Dir = enum
        north, south, west, east
      HoleyDir = enum
        hNorth = 1, hSouth = 3, hWest = 6, hEast = 12

    check encodeDecodesDoc @[north, south]

    when defined(kdlDecoderAllowHoleyEnums):
      check encodeDecodesDoc @[HoleyDir(2), hSouth]

  test "Chars":
    check encodeDecodesDoc @['a', 'b', 'c']
    check encodeDecodesNode('#', "node")

  test "Extra":
    check encodeDecodesNode(1, "node")

    check encodeDecodesNode(true, "node")

    # check encodeDecodes @[cstring nil, cstring "not null"]

  test "Custom":
    check encodeDecodesDoc dateTime(2022, mOct, 15, 12, 10)

    check encodeDecodesDoc dateTime(2022, mOct, 15, 12, 04)

    check encodeDecodesDoc dateTime(2000, mOct, 15)

  test "All":
    let obj = AllObj(
      id: 2000i64, id2: 20000u32,
      name: ("ai", true), subrange: 0.5f,
      node: initKNode("node"), val: initKVal(true),
      doc: @[initKNode("first"), initKNode("second")],
      items: @['o', 'v', 'e'], items2: [114, 108],
      items3: {'o', 'r', 'd'}, items4: ["ognmoma", "vole"].toHashSet,
      items5: ["rame", "kisu"].toOrderedSet,
      obj: MyObj(kind: moString, stringV: "mclitneen", kind2: moInt, intV2: 0xdead),
      table: {"mlicb": 'F'}.toTable, table2: {"hakumuse": 500i16}.toOrderedTable,
      table3: {"mlicb": "ikudais", "lang": "jp"}.newStringTable,
      option: meWest.some
    )
    check encodeDecodesDoc obj

