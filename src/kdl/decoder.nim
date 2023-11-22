## ## Decoder
## This module implements a deserializer for KDL documents, nodes and values into different types and objects:
## - `char`
## - `bool`
## - `string`
## - `Option[T]`
## - `SomeNumber`
## - `StringTableRef`
## - `enum` and `HoleyEnum`
## - `KdlVal`
## - `seq[T]` and `array[I, T]`
## - `set[Ordinal]`, `HashSet[A]` and `OrderedSet[A]`
## - `Table[string, T]` and `OrderedTable[string, T]`
## - `object`, `ref` and `tuple` (including object variants with multiple discriminator fields)
## - Plus any type you implement.
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
  description "kats document language"
  authors "Kat Marchán <kzm@zkat.tech>"
  license-file "LICENSE.md"
  edition "2018"
}
dependencies {
  nom "6.0.1"
  thiserror "1.0.22"
}""")

  const package = doc.decodeKdl(Package, "package")
  const dependencies = doc.decodeKdl(Deps, "dependencies")

  assert package == Package(
    name: "kdl",
    version: "0.0.0",
    authors: @["Kat Marchán <kzm@zkat.tech>"].some,
    description: "kats document language".some,
    licenseFile: "LICENSE.md".some,
    edition: "2018".some
  )
  assert dependencies == {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable

## ### Custom Hooks
## #### Init hook
## With init hooks you can initialize types with default values before decoding.
## Use the following signature when overloading `decodeInitKdl`:
## ```nim
## proc initHookKdl*[T](v: var T) =
## ```
## *Note: by default if you change a discrimantor field of an object variant in an init hook (`v.kind = kInt`), it will throw a compile error. If you want to disable it, compile with the following flag -d:kdlDecoderNoCaseTransitionError.*
runnableExamples:
  import kdl

  type Foo = object
    x*: int

  proc initHookKdl*(v: var Foo) =
    v.x = 5 # You may also do `v = Foo(x: 5)`

  assert parseKdl("").decodeKdl(Foo) == Foo(x: 5)

## #### Post hook
## Post hooks are called after decoding any (default, for custom decode hooks you have to call `postHookable(v)` explicitly) type.
##
## Overloads of `postHook` must use the following signature:
## ```nim
## proc postHookKdl(v: var MyType)
## ```
runnableExamples:
  import kdl

  type Foo = object
    x*: int

  proc postHookKdl(v: var Foo) =
    inc v.x

  assert parseKdl("x 1").decodeKdl(Foo) == Foo(x: 2) # 2 because x after postHook got incremented by one

## #### Enum hook
## Enum hooks are useful for parsing enums in a custom manner.
##
## You can overload `enumHook` with two different signatures:
## ```nim
## proc enumHookKdl(a: string, v: var MyEnum)
## ```
## ```nim
## proc enumHookKdl(a: int, v: var MyEnum)
## ```
## *Note: by default decoding an integer into a holey enum raises an error, to override this behaviour compile with -d:kdlDecoderAllowHoleyEnums.*
runnableExamples:
  import std/[strformat, strutils]
  import kdl

  type MyEnum = enum
    meNorth, meSouth, meWest, meEast

  proc enumHookKdl(a: string, v: var MyEnum) =
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

  proc enumHookKdl(a: int, v: var MyEnum) =
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

  assert parseKdl("""
  node "north" "south" "west" "east"
  """).decodeKdl(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

  assert parseKdl("""
  node 0xbeef 0xcafe 0xface 0xdead
  """).decodeKdl(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

## #### Rename hook
## As its name suggests, a rename hook renames the fields of an object in any way you want.
##
## Follow this signature when overloading `renameHook`:
## ```nim
## proc renameHookKdl(_: typedesc[MyType], fieldName: var string)
## ```
runnableExamples:
  import kdl

  type Foo = object
    kind*: string
    list*: seq[int]

  proc renameHookKdl(_: typedesc[Foo], fieldName: var string) =
    fieldName =
      case fieldName
      of "type":
        "kind"
      of "array":
        "list"
      else:
        fieldName

  # Here we rename "type" to "kind" and "array" to "list".
  assert parseKdl("""
  type "string"
  array 1 2 3
  """).decodeKdl(Foo) == Foo(kind: "string", list: @[1, 2, 3])
## #### Decode hook
## Use custom decode hooks to decode your types, your way.
##
## To do it you have to overload the `decodeKdl` procedure with the following signature:
## ```nim
## proc decodeKdl*(a: KdlSome, v: var MyType) =
## ```
## Where `KdlSome` is one of `KdlDoc`, `KdlNode` or `KdlVal`:
## - `KdlDoc` is called to decode a document.
## - `KdlNode` is called to decode a node inside a document or inside another node's children.
## - `KdlVal` is called to decode arguments or properties of a node.
## To use all the hooks explained above you don't call them with `initHookKdl` instead use `decodeInitKdl`:
## . `decodeInitKdl` instead of `initHookKdl`.
## . `decodePostKdl` instead of `postHookKdl`.
## . `decodeEnumKdl` instead of `enumHookKdl`.
## . `decodeRenameKdl` instead of `renameHookKdl`.
## *Note: you can check the signatures of those procedures below in the documentation.*
## Read the following example:
runnableExamples:
  import std/times
  import kdl
  import kdl/utils # kdl/utils define some useful internal procedures such as `eqIdent`, which checks the equality of two strings ignore case, underscores and dashes in an efficient way.

  proc decodeKdl*(a: KdlVal, v: var DateTime) =
    decodeInitKdl(v)
    assert a.isString
    v = a.getString.parse("yyyy-MM-dd")
    decodePostKdl(v)

  proc decodeKdl*(a: KdlNode, v: var DateTime) =
    decodeInitKdl(v)
    assert a.args.len in {1, 3, 6}
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
      discard

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

    decodePostKdl(v)

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
      if node.name.eqIdent "year":
        node.decodeKdl(year)
      elif node.name.eqIdent "month":
        node.decodeKdl(month)
      elif node.name.eqIdent "day":
        node.decodeKdl(day)
      elif node.name.eqIdent "hour":
        node.decodeKdl(hour)
      elif node.name.eqIdent "minute":
        node.decodeKdl(minute)
      elif node.name.eqIdent "second":
        node.decodeKdl(second)
      elif node.name.eqIdent "nanosecond":
        node.decodeKdl(nanosecond)

    v = dateTime(year, month, day, hour, minute, second, nanosecond)

    decodePostKdl(v)

  # Here we use the KdlDoc overload
  assert parseKdl("""
  year 2022
  month 10 // or "October"
  day 15
  hour 12
  minute 10
  """).decodeKdl(DateTime) == dateTime(2022, mOct, 15, 12, 10)

  # Here we use the KdlNode overload
  assert parseKdl("date 2022 \"October\" 15 12 04 00").decodeKdl(DateTime, "date") == dateTime(2022, mOct, 15, 12, 04)
  # And here we use the KdlVal overload
  assert parseKdl("author birthday=\"2000-10-15\" name=\"Nobody\"")[0]["birthday"].decodeKdl(DateTime) == dateTime(2000, mOct, 15)
##
## ----------
##
## As you may have noticed if you looked through the API, there is `decodeInitKdl` and `initHookable`, `enumHook` and `enumHookable`.
## Any hook suffixed -able, actually calls the hook itself after making sure there is an overload that matches it.
## You should not overload these as they are meant for internal use, the reason they are exported is because when implementing your custom decode hooks you may also want to use them.
##
## So remember: for custom behaviour, overload -hook suffixed procedures; to make use of these hooks call the -hookable suffixed procedures, you don't call these unless you want their behavior within your custom decode hooks.
##
## ----------
##
## All of these examples were taken out from the [tests](https://github.com/Patitotective/kdl-nim/blob/main/tests/test_serializer.nim), so if you need more, check them out.

import std/[typetraits, strformat, strutils, strtabs, tables, sets]
import nodes, utils, types

# ----- Index -----

proc rfindNode(a: KdlDoc, s: string): Option[KdlNode]
proc findProp(a: KdlNode, s: string): Option[KdlVal]
proc rfindRenameNode(a: KdlDoc, s: string, T: typedesc): Option[KdlNode]
proc findRenameProp(a: KdlNode, s: string, T: typedesc): Option[KdlVal]

proc initHookKdl*[T](v: var ref T)
proc initHookKdl*[T](v: var T)
proc enumHookKdl*[T: enum](a: int, v: var T)
proc enumHookKdl*[T: enum](a: string, v: var T)
proc enumHookKdl*(a: KdlVal, v: var enum)
proc postHookKdl*(v: var auto)
proc renameHookKdl*(a: typedesc, fieldName: var string)
proc decodeInitKdl*(v: var auto)
proc decodeEnumKdl*[T: enum](a: auto, v: var T)
proc decodePostKdl*(v: var auto)
proc decodeRenameKdl*(a: typedesc, fieldName: string): string

proc decodeKdl*[T](a: KdlSome, _: typedesc[T]): T
proc decodeKdl*[T: KdlSome](a: T, v: var T)

proc decodeKdl*(a: KdlDoc, v: var auto, name: string)
proc decodeKdl*[T](a: KdlDoc, _: typedesc[T], name: string): T
proc decodeKdl*(a: KdlDoc, v: var Object)
proc decodeKdl*(a: KdlDoc, v: var List)
proc decodeKdl*[T](a: KdlDoc, v: var SomeTable[string, T])
proc decodeKdl*(a: KdlDoc, v: var StringTableRef)
proc decodeKdl*[T](a: KdlDoc, v: var SomeSet[T])
proc decodeKdl*[T: Ordinal](a: KdlDoc, v: var set[T])
proc decodeKdl*[T](a: KdlDoc, v: var ref T)

proc decodeKdl*(a: KdlNode, v: var Object)
proc decodeKdl*(a: KdlNode, v: var List)
proc decodeKdl*[T](a: KdlNode, v: var SomeTable[string, T])
proc decodeKdl*(a: KdlNode, v: var StringTableRef)
proc decodeKdl*[T](a: KdlNode, v: var SomeSet[T])
proc decodeKdl*[T: Ordinal](a: KdlNode, v: var set[T])
proc decodeKdl*[T](a: KdlNode, v: var Option[T])
proc decodeKdl*[T](a: KdlNode, v: var ref T)
proc decodeKdl*(a: KdlNode, v: var auto)

proc decodeKdl*[T: Value](a: KdlVal, v: var T)
proc decodeKdl*[T: enum](a: KdlVal, v: var T)
proc decodeKdl*(a: KdlVal, v: var char)
# proc decodeKdl*(a: KdlVal, v: var cstring)
proc decodeKdl*[T: array](a: KdlVal, v: var T)
proc decodeKdl*[T: not KdlNode](a: KdlVal, v: var seq[T])
proc decodeKdl*(a: KdlVal, v: var Object)
proc decodeKdl*[T](a: KdlVal, v: var SomeSet[T])
proc decodeKdl*[T: Ordinal](a: KdlVal, v: var set[T])
proc decodeKdl*[T](a: KdlVal, v: var Option[T])
proc decodeKdl*[T](a: KdlVal, v: var ref T)
proc decodeKdl*[T: KdlNode or KdlDoc](a: KdlVal, v: var T)

# ----- Utils -----

proc rfindNode(a: KdlDoc, s: string): Option[KdlNode] =
  for i in countdown(a.high, 0):
    if a[i].name.eqIdent s:
      return a[i].some

proc findProp(a: KdlNode, s: string): Option[KdlVal] =
  for key, val in a.props:
    if key.eqIdent s:
      return val.some

proc rfindRenameNode(a: KdlDoc, s: string, T: typedesc): Option[KdlNode] =
  for i in countdown(a.high, 0):
    if decodeRenameKdl(T, a[i].name).eqIdent s:
      return a[i].some

proc findRenameProp(a: KdlNode, s: string, T: typedesc): Option[KdlVal] =
  for key, val in a.props:
    if decodeRenameKdl(T, key).eqIdent s:
      return val.some

# ----- Hooks -----

proc initHookKdl*[T](v: var ref T) =
  v = new T

proc initHookKdl*[T](v: var T) = # https://github.com/nim-lang/Nim/issues/22878
  when T is range:
    v = T.low

proc enumHookKdl*[T: enum](a: int, v: var T) =
  when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
    fail &"forbidden int-to-HoleyEnum conversion ({a} -> {$T}); compile with -d:kdlDecoderAllowHoleyEnums"
  else:
    v = T(a)

proc enumHookKdl*[T: enum](a: string, v: var T) =
  v = parseEnum[T](a)

proc enumHookKdl*(a: KdlVal, v: var enum) =
  case a.kind
  of KString:
    decodeEnumKdl(a.getString, v)
  of KInt:
    decodeEnumKdl(a.get(int), v)
  else:
    fail &"expected string or int in {a}"

proc postHookKdl*(v: var auto) = discard

proc renameHookKdl*(a: typedesc, fieldName: var string) = discard

proc decodeInitKdl*(v: var auto) =
  when not defined(kdlDecoderNoCaseTransitionError):
    {.push warningAsError[CaseTransition]: on.}
  mixin initHookKdl
  initHookKdl(v)

proc decodeEnumKdl*[T: enum](a: auto, v: var T) =
  mixin enumHookKdl
  enumHookKdl(a, v)

proc decodePostKdl*(v: var auto) =
  mixin postHookKdl
  postHookKdl(v)

proc decodeRenameKdl*(a: typedesc, fieldName: string): string =
  mixin renameHookKdl
  result = fieldName
  renameHookKdl(a, result)

# ----- KdlSome -----

proc decodeKdl*[T](a: KdlSome, _: typedesc[T]): T =
  ## Shortcut to allow:
  ## ```nim
  ## assert decodeKdl(doc, MyObj) is MyObj
  ## ```
  ## Instead of:
  ## ```nim
  ## var obj: MyObj
  ## decodeKdl(doc, obj)
  ## ```
  # var result: T
  result = default T # Otherwise 'requires initialization' error
  decodeKdl(a, result)

proc decodeKdl*[T: KdlSome](a: T, v: var T) =
  decodeInitKdl(v)
  v = a
  decodePostKdl(v)

# proc decodeKdl*(a: KdlSome, v: var proc) =
#   fail &"{$typeof(v)} not implemented for {$typeof(a)}"

# ----- KdlDoc -----

proc decodeKdl*(a: KdlDoc, v: var auto, name: string) =
  ## Decodes the last node named name in a into v
  let node = a.rfindNode(name)

  if node.isNone:
    fail "Could not find any node named " & name.quoted & " in " & $a
  else:
    decodeKdl(node.get, v)

proc decodeKdl*[T](a: KdlDoc, _: typedesc[T], name: string): T =
  decodeKdl(a, result, name)

proc decodeKdl*(a: KdlDoc, v: var Object) =
  type T = typeof(v)
  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    var count = 0
    for _, field in v.fieldPairs:
      if count < a.len:
        decodeKdl(a[count], field)
      else:
        fail &"Expected a node at index {count} in {a}"

      inc count
  else:
    const discKeys = getDiscriminants(T) # Object variant discriminator keys

    when discKeys.len > 0: # When it's an object variant
      template discriminatorSetter(key, typ): untyped =
        # Tries to find a node with the discriminator key
        let discrNode = a.rfindRenameNode(key, T)

        if discrNode.isSome:
          decodeKdl(discrNode.get, typ) # Last expression is the field value
        else: # If the discriminator node isn't found, use the default value
          when defined(kdlDecoderNoDiscriminatorError):
            fail &"Expected discriminator field {key} in {a}"

          var x: typeofdesc typ
          decodeInitKdl(x)
          x # Last expression is the field value

      v = initCaseObject(T, discriminatorSetter)

    decodeInitKdl(v)

    for fieldName, field in v.fieldPairs:
      when fieldName notin discKeys: # Ignore discriminant field name
        let node = a.rfindRenameNode(fieldName, T)

        if node.isSome:
          decodeKdl(node.get, field)
        else:
          decodeInitKdl(field)

  decodePostKdl(v)

proc decodeKdl*(a: KdlDoc, v: var List) =
  when v is seq:
    v.setLen a.len

  for e, node in a:
    decodeKdl(node, v[e])

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlDoc, v: var SomeTable[string, T]) =
  v.clear()

  for node in a:
    v[node.name] = decodeKdl(node, T)

  decodePostKdl(v)

proc decodeKdl*(a: KdlDoc, v: var StringTableRef) =
  if v.isNil:
    v = newStringTable()
  else:
    v.clear()

  for node in a:
    v[node.name] = decodeKdl(node, string)

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlDoc, v: var SomeSet[T]) =
  v.clear()

  for node in a:
    v.incl decodeKdl(node, T)

  decodePostKdl(v)

proc decodeKdl*[T: Ordinal](a: KdlDoc, v: var set[T]) =
  v.reset()
  for node in a:
    v.incl decodeKdl(node, T)

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlDoc, v: var ref T) =
  if v.isNil:
    v = new T

  decodeKdl(a, v[])

# ----- KdlNode -----

proc decodeKdl*(a: KdlNode, v: var Object) =
  ## When searching for fields, gives priority to properties over children.
  ## ```
  ## node kind=1 name="a" { kind 2; name "b" }
  ## ```
  ## The above node would prefer kind=1 and name="a" over kind 2; name "b"
  type T = typeof(v)
  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    var count = 0
    for _, field in v.fieldPairs:
      if count < a.args.len:
        decodeKdl(a.args[count], field)
      elif count < a.children.len:
        decodeKdl(a.children[count], field)
      else:
        fail &"Expected argument or child at index {count} in {a} "

      inc count
  else:
    const discKeys = getDiscriminants(T) # Object variant discriminator keys
    when discKeys.len > 0: # When it's an object variant
      template discriminatorSetter(key, typ): untyped =
        # Tries to find a node with the discriminator key
        let discNode = a.children.rfindRenameNode(key, T)
        let discProp = a.findRenameProp(key, T)
        if discProp.isSome:
          decodeKdl(discProp.get, typ) # Last expression is the field value
        elif discNode.isSome:
          decodeKdl(discNode.get, typ) # Last expression is the field value
        else: # If the discriminator node isn't found, use the default value
          when defined(kdlDecoderNoDiscriminatorError):
            fail &"Expected discriminator field {key} in {a}"

          var x: typeofdesc typ
          decodeInitKdl(x)
          x # Last expression is the field value

      v = initCaseObject(T, discriminatorSetter)
    decodeInitKdl(v)

    for fieldName, field in v.fieldPairs:
      when fieldName notin discKeys: # Ignore discriminant field name
        let prop = a.findRenameProp(fieldName, T)
        let node = a.children.rfindRenameNode(fieldName, T)

        if prop.isSome:
          decodeKdl(prop.get, field)
        elif node.isSome:
          decodeKdl(node.get, field)
        else:
          decodeInitKdl(field)

  decodePostKdl(v)

proc decodeKdl*(a: KdlNode, v: var List) =
  ## Decodes a arguments and children (in that order) into v.
  when v is seq:
    v.setLen a.args.len + a.children.len

  var count = 0

  for arg in a.args:
    if count >= v.len: break
    decodeKdl(arg, v[count])

    inc count

  for child in a.children:
    if count >= v.len: break
    decodeKdl(child, v[count])
    inc count

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlNode, v: var SomeTable[string, T]) =
  v.clear()

  for key, val in a.props:
    v[key] = decodeKdl(val, T)

  for node in a.children:
    v[node.name] = decodeKdl(node, T)

  decodePostKdl(v)

proc decodeKdl*(a: KdlNode, v: var StringTableRef) =
  if v.isNil:
    v = newStringTable()
  else:
    v.clear()

  for key, val in a.props:
    v[key] = decodeKdl(val, string)

  for node in a.children:
    v[node.name] = decodeKdl(node, string)

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlNode, v: var SomeSet[T]) =
  v.clear()

  for arg in a.args:
    v.incl decodeKdl(arg, T)

  for child in a.children:
    v.incl decodeKdl(child, T)

  decodePostKdl(v)

proc decodeKdl*[T: Ordinal](a: KdlNode, v: var set[T]) =
  v.reset()

  for arg in a.args:
    v.incl decodeKdl(arg, T)

  for child in a.children:
    v.incl decodeKdl(child, T)

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlNode, v: var Option[T]) =
  ## Decodes a into v, v is none when a's arguments, properties and children are empty.

  v =
    if a.args.len == 0 and a.props.len == 0 and a.children.len == 0:
      none[T]()
    else:
      decodeKdl(a, T).some

  decodePostKdl(v)

proc decodeKdl*(a: KdlNode, v: var KdlNode) =
  v = a

proc decodeKdl*[T](a: KdlNode, v: var ref T) =
  if v.isNil:
    v = new T

  decodeKdl(a, v[])

proc decodeKdl*(a: KdlNode, v: var auto) =
  ## Decodes a's first argument into v
  check a.args.len == 1, &"expected exactly one argument in {a}"
  decodeKdl(a.args[0], v)

# ----- KdlVal -----

proc decodeKdl*[T: Value](a: KdlVal, v: var T) =
  ## Decodes a into v using `nodes.get`
  v = a.get(typeof v)
  decodePostKdl(v)

proc decodeKdl*[T: enum](a: KdlVal, v: var T) =
  ## Decodes a into v when a is a string or int using `decodeEnumKdl`
  decodeInitKdl(v)
  decodeEnumKdl(a, v)
  decodePostKdl(v)

proc decodeKdl*(a: KdlVal, v: var char) =
  ## Decoes a into v when a is one-character-long string
  check a.isString and a.getString.len == 1, &"expected one-character-long string in {a}"
  v = a.getString[0]
  decodePostKdl(v)

# Not implemented since it's unclear to me where and how should the cstring be stored
# proc decodeKdl*(a: KdlVal, v: var cstring) =
#   case a.kind
#   of KNull:
#     v = nil
#   of KString:
#     v = cstring a.getString
#   else:
#     fail &"expected string or null in {a}"

#   decodePostKdl(v)

proc decodeKdl*[T: array](a: KdlVal, v: var T) =
  when v.len == 1:
    decodeKdl(a, v[0])
  else:
    fail &"{$typeof(v)} not implemented for {$typeof(a)}, expected a one-length array"

# We do 'not KdlNode' so it doesn't match KdlDoc (which is seq[KdlNode])
proc decodeKdl*[T: not KdlNode](a: KdlVal, v: var seq[T]) =
  v.setLen 1
  decodeKdl(a, v[0])

proc decodeKdl*(a: KdlVal, v: var Object) =
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

proc decodeKdl*[T](a: KdlVal, v: var SomeSet[T]) =
  v.clear()

  v.incl decodeKdl(a, T)

  decodePostKdl(v)

proc decodeKdl*[T: Ordinal](a: KdlVal, v: var set[T]) =
  v.reset()

  v.incl decodeKdl(a, T)

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlVal, v: var Option[T]) =
  ## Decodes a into v, v is none when a is null.

  if a.isNull:
    v = none[T]()
  else:
    v = decodeKdl(a, T).some

  decodePostKdl(v)

proc decodeKdl*[T](a: KdlVal, v: var ref T) =
  if a.isNull:
    v = nil
  else:
    fail &"{$typeof(v)} not implemented for {$typeof(a)}"

proc decodeKdl*[T: KdlNode or KdlDoc](a: KdlVal, v: var T) =
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

