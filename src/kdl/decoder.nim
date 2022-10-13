## ## Decoder
## This modules implements deserializing KDL documents, nodes and values into different types and objects, by default:
## - `char`
## - `bool`
## - `string`
## - `KdlVal`
## - `Option[T]`
## - `SomeNumber`
## - `enum` and `HoleyEnum`
## - `seq[T]` and `array[I, T]`
## - `object`, `ref` and `tuple`
## - `Table[string, T]` and `OrderedTable[string, T]`
## Consider the following example:
runnableExamples:
  import kdl

  type
    Package = object
      name*, version*: string
      authors*: Option[seq[string]]
      description*, licenseFile*, edition*: Option[string]

    Deps = Table[string, string]

  const doc = parseKdl("""
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

  const package = doc.decode(Package, "package")
  const dependencies = doc.decode(Deps, "dependencies")

  assert package == Package(
    name: "kdl", 
    version: "0.0.0", 
    authors: @["Kat Marchán <kzm@zkat.tech>"].some, 
    description: "kat's document language".some, 
    licenseFile: "LICENSE.md".some, 
    edition: "2018".some
  )
  assert dependencies == {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable
## ### Custom decoders
## You can also implement your own `decode` procedures for specific types by overloading the `decode` procedure, with the following signature `proc decode*(obj: KdlDoc or KdlNode or KdlVal, x: var T)`.
## Where the first parameter is either a document, node or value and the second parameter is the decoding result.
## 
## Consider the following example:
runnableExamples:
  import std/times
  import kdl

  proc decode*(obj: KdlNode, x: var DateTime) = ## Remember to mark it as exported *
    assert obj.len == 1
    x = obj[0].getString.parse("yyyy-MM-dd")

    if "hour" in obj:
      x.hour = obj["hour"].getInt
    if "minute" in obj:
      x.minute = obj["minute"].getInt
    if "second" in obj:
      x.second = obj["second"].getInt
    if "nanosecond" in obj:
      x.nanosecond = obj["nanosecond"].getInt
    if "offset" in obj:
      x.utcOffset = obj["offset"].get(int)

  let date = parseKdl("date \"2000-12-31\" hour=3").decode(DateTime, "date")
  assert date.year == 2000
  assert date.month == mDec
  assert date.hour == 3

## Here we use `obj: KdlNode` instead of `KdlDoc` or `KdlVal` because we wanted to parse a whole node as a DateTime, we could also use:
## - `KdlDoc` if we wanted to parse a whole document as a DateTime:
## ```kdl
## year 2008
## month 05
## day 14
## ```
## - `KdlVal` if we wanted to parse a single value as a DateTime:
## ```kdl
## package date="2022-07-07" name="Nanda"
## ```
## 
## ### Compile Flags
## - `-d:kdlDecoderNameNotFoundError` to error when a node cannot be found for a tuple or object field. 
## - `-d:kdlDecoderAllowHoleyEnums` to allow unsafe `int` to `HoleyEnum` conversion.

{.used.}

import std/[typetraits, strutils, tables]
import nodes, utils

type
  Value = (SomeNumber or string or bool or KdlVal)
  Object = ((object or ref or tuple) and not KdlVal)

proc cmpIgnoreStyle(a, b: openArray[char]): int =
  let aLen = a.len
  let bLen = b.len
  var i = 0
  var j = 0

  while true:
    while i < aLen and a[i] in {'_', '-'}: inc i
    while j < bLen and b[j] in {'_', '-'}: inc j
    let aa = if i < aLen: toLowerAscii(a[i]) else: '\0'
    let bb = if j < bLen: toLowerAscii(b[j]) else: '\0'
    result = ord(aa) - ord(bb)
    if result != 0: return result
    # the characters are identical:
    if i >= aLen:
      # both cursors at the end:
      if j >= bLen: return 0
      # not yet at the end of 'b':
      return -1
    elif j >= bLen:
      return 1
    inc i
    inc j

proc eqIdent(a, b: openArray[char]): bool = cmpIgnoreStyle(a, b) == 0

template error(msg: openArray[char]) = 
  raise newException(KdlError, msg)

template error(x: bool, msg: openArray[char]) = 
  if x:
    error(msg)

proc decode*(obj: KdlVal, x: var char) = 
  runnableExamples:
    import kdl
    assert parseKdl("rows \"a\" \"b\" \"c\"").decode(seq[char], "rows") == @['a', 'b', 'c']

  error not obj.isString or obj.getString.len != 1, "expected a 1 character long string for " & $obj

  x = obj.getString[0]

proc decode*[T: enum](obj: KdlVal, x: var T) = 
  ## Decodes obj into T.
  ## - obj must be a string or integer.
  ## - compile with `-d:kdlDecoderAllowHoleyEnums` to allow converting `int` to `HoleyEnum`
  runnableExamples:
    import kdl

    type Dir = enum
      North, South, West, East

    assert parseKdl("dir \"North\" 1").decode(seq[Dir], "dir") == @[North, South]

  error obj.kind notin {KString, KInt}, "expected string or int for " & $T & "; got " & $obj.kind
  
  if obj.isString:
    try:
      x = parseEnum[T](obj.getString)
    except ValueError as error:
      error.msg.add " for " & $T
      raise
  else:
    when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
      error $T & " is a holey enum; compile with -d:kdlDecoderAllowHoleyEnums to convert to holey enums"
    else:
      x = T(obj.getInt)

proc decode*[T: Value](obj: KdlVal, x: var T) = 
  ## Decodes obj into T.
  x = obj.get(T)

proc decode*[T: not Object](obj: KdlNode, x: var T) = 
  ## Decodes obj's first argument into T.
  ## - obj must have exactly one argument
  error obj.len != 1, "expected exactly one argument; got " & $obj.len
  obj[0].decode(x)

proc decode*[T](obj: KdlVal, x: var seq[T]) = 
  runnableExamples:
    import kdl
    assert parseKdl("node 1 2 3").decode(seq[seq[int]], "node") == @[@[1], @[2], @[3]]

  x.setLen(1)
  obj.decode(x[0])

proc decode*[T](obj: KdlNode, x: var seq[T]) = 
  runnableExamples:
    import kdl
    assert parseKdl("node 1 2 3").decode(seq[int], "node") == @[1, 2, 3]

  x.setLen(obj.len)
  for e, arg in obj.args:
    arg.decode(x[e])

proc decode*[T](obj: KdlDoc, x: var seq[T]) = 
  runnableExamples:
    import kdl
    type Foo = object
      a*, b*: int

    assert parseKdl("node {a 1; b 2}; node {a 3; b 3}").decode(seq[Foo]) == @[Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    assert parseKdl("node 1; node 2").decode(seq[int]) == @[1, 2]

  x.setLen(obj.len)
  for e, node in obj:
    node.decode(x[e])

proc decode*[I, T](obj: KdlVal, x: var array[I, T]) = 
  runnableExamples:
    import kdl
    assert parseKdl("node 1 2 3").decode(seq[array[1, int]], "node") == @[[1], [2], [3]]

  obj.decode(x[0])

proc decode*[I, T](obj: KdlNode, x: var array[I, T]) = 
  runnableExamples:
    import kdl
    assert parseKdl("node 1 2 3").decode(array[3, int], "node") == [1, 2, 3]

  for e, arg in obj.args:
    if e >= x.len: break

    arg.decode(x[e])

proc decode*[I, T](obj: KdlDoc, x: var array[I, T]) = 
  runnableExamples:
    import kdl
    type Foo = object
      a*, b*: int

    assert parseKdl("node {a 1; b 2}; node {a 3; b 3}").decode(array[2, Foo]) == [Foo(a: 1, b: 2), Foo(a: 3, b: 3)]
    assert parseKdl("node 1; node 2").decode(array[2, int]) == [1, 2]

  for e, node in obj:
    if e >= x.len: break

    node.decode(x[e])

proc decode*[T](obj: KdlNode, x: var Option[T]) = 
  runnableExamples:
    import kdl

    assert parseKdl("node \"Nah\"; node \"Pat\"; node").decode(seq[Option[string]]) == @["Nah".some, "Pat".some, string.none]

  x = 
    try:
      obj.decode(T).some
    except KdlError:
      T.none

proc decode*[T](obj: KdlVal, x: var Option[T]) = 
  runnableExamples:
    import kdl

    type Person = object
      name*: string
      surname*: Option[string]

    assert parseKdl("node name=\"Beef\"; node name=\"Pat\" surname=\"ito\"").decode(seq[Person]) == @[Person(name: "Beef", surname: none(string)), Person(name: "Pat", surname: some("ito"))]

  x = 
    try:
      obj.decode(T).some
    except KdlError:
      T.none

proc decode*[T](obj: KdlDoc, x: var Table[string, T]) = 
  runnableExamples:
    import kdl

    assert parseKdl("key \"value\"; alive true").decode(Table[string, KdlVal]) == {
      "alive": true.initKVal, 
      "key": "value".initKVal
    }.toTable

  for node in obj:
    x[node.name] = node.decode(T)

proc decode*[T](obj: KdlNode, x: var Table[string, T]) = 
  runnableExamples:
    import kdl

    assert parseKdl("person age=10 name=\"Ringabout\" {other-name \"flywind\"}").decode(Table[string, KdlVal], "person") == {
      "name": "Ringabout".initKVal, 
      "age": 10.initKVal, 
      "other-name": "flywind".initKVal
    }.toTable

  for key, val in obj.props:
    x[key] = val.decode(T)

  obj.children.decode(x)

proc decode*[T](obj: KdlDoc, x: var OrderedTable[string, T]) = 
  runnableExamples:
    import kdl

    assert parseKdl("key \"value\"; alive true").decode(OrderedTable[string, KdlVal]) == {
      "key": "value".initKVal, 
      "alive": true.initKVal
    }.toOrderedTable

  for node in obj:
    x[node.name] = node.decode(T)

proc decode*[T](obj: KdlNode, x: var OrderedTable[string, T]) = 
  runnableExamples:
    import kdl

    assert parseKdl("person age=10 name=\"Ringabout\" {other-name \"flywind\"}").decode(OrderedTable[string, KdlVal], "person") == {
        "age": 10.initKVal, 
        "name": "Ringabout".initKVal, 
        "other-name": "flywind".initKVal
      }.toOrderedTable

  for key, val in obj.props:
    x[key] = val.decode(T)

  obj.children.decode(x)

proc decode*[T: Object](obj: KdlNode, x: var T) = 
  runnableExamples:
    import kdl

    type Person = object
      name*: string
      age*: int

    assert parseKdl("person age=20 {name \"Rika\"}").decode(Person, "person") == Person(age: 20, name: "Rika")
    assert parseKdl("person age=20 {name \"Rika\"}").decode(tuple[age: int, name: string], "person") == (age: 20, name: "Rika")

  when x is ref:
    if x.isNil:
      x = new T

  for field, val in (when T is ref: x[].fieldPairs else: x.fieldPairs):
    var found = false
    for key, _ in obj.props:
      if key.eqIdent field:
        found = true
        try:
          obj[key].decode(val)
        except KdlError as error:
          error.msg.add " in " & field.quoted
          raise

    when defined(kdlDecoderNameNotFoundError):
      if not found:
        raise newException(KdlError, "Could not find a any node for the " & field.quoted & " field")

  obj.children.decode(x)

proc decode*[T: Object](obj: KdlDoc, x: var T) = 
  runnableExamples:
    import kdl

    type Game = object
      name*, version*, author*, license*: string

    assert parseKdl("name \"Mindustry\"; version \"126.2\"; author \"Anuken\"; license \"GNU General Public License v3.0\"").decode(Game) == Game(name: "Mindustry", version: "126.2", author: "Anuken", license: "GNU General Public License v3.0")

  when x is ref:
    if x.isNil:
      x = new T

  for field, val in (when T is ref: x[].fieldPairs else: x.fieldPairs):
    var found = false
    for node in obj:
      if node.name.eqIdent field:
        found = true
        try:
          node.decode(val)
        except KdlError as error:
          error.msg.add " in " & field.quoted
          raise

    when defined(kdlDecoderNameNotFoundError):
       if not found:
         raise newException(ValueError, "Could not find a any node for " & field.quoted)

proc decode*[A: KdlDoc or KdlVal or KdlNode, B](obj: A, z: typedesc[B]): B = 
  ## Helper in-place procedure for decoding since decode procedures are out-of-place procedures.
  ## 
  ## i.e.:
  runnableExamples:
    import kdl

    ## With this procedure you can call decoders like this
    assert parseKdl("node 1").decode(int, "node") == 1

    ## And it will convert them into this
    var result: int
    parseKdl("node 1").decode(result, "node")
    assert result == 1

  obj.decode(result)

proc decode*[T](obj: KdlDoc, x: var T, name: string) = 
  ## Decodes the last node named name
  runnableExamples:
    import kdl

    assert parseKdl("node true").decode(bool, "node") == true

  var found = -1
  for e in countdown(obj.high, 0):
    if obj[e].name.eqIdent name:
      found = e
      break

  if found < 0:
    error "Could not find a any node for " & name.quoted

  try:
    obj[found].decode(x)
  except KdlError as error:
    error.msg.add " in " & name
    raise

proc decode*[T](obj: KdlDoc, x: typedesc[T], name: string): T = 
  ## Same as [decode](#decode,A,typedesc[B]) but for [decode](#decode,KdlDoc,T,string)
  obj.decode(result, name)
