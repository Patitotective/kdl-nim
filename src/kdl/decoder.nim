## ## Decoder
## This modules implements a deserializer for KDL documents, nodes and values into different types and objects:
## - `char`
## - `bool`
## - `Option[T]`
## - `SomeNumber`
## - `StringTableRef`
## - `enum` and `HoleyEnum`
## - `string` and `cstring`
## - `KdlVal` (object variant)
## - `seq[T]` and `array[I, T]`
## - `HashSet[A]` and `OrderedSet[A]`
## - `Table[string, T]` and `OrderedTable[string, T]`
## - `object`, `ref` and `tuple` (including object variants)
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

## ### Custom Decode Hooks
## See the tests
## 

import std/[strformat, typetraits, strutils, strtabs, tables, sets]
import nodes, utils, types

proc rfind(a: KdlDoc, s: string): Option[KdlNode] = 
  for i in countdown(a.high, 0):
    if a[i].name.eqIdent s:
      return a[i].some

proc find(a: KdlNode, s: string): Option[KdlVal] = 
  for key, val in a.props:
    if key.eqIdent s:
      return val.some

# ----- Index -----

proc decode*(a: KdlSome, v: var auto)
proc decode*[T](a: KdlSome, _: typedesc[T]): T

proc decode*(a: KdlDoc, v: var auto, name: string)
proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T

proc decodeHook*[T: KdlSome](a: T, v: var T)
proc decodeHook*(a: KdlSome, v: var proc)

proc decodeHook*(a: KdlDoc, v: var Object)
proc decodeHook*(a: KdlDoc, v: var ref)
proc decodeHook*(a: KdlDoc, v: var List)

proc decodeHook*(a: KdlNode, v: var Object)
proc decodeHook*(a: KdlNode, v: var ref)
proc decodeHook*(a: KdlNode, v: var List)
proc decodeHook*(a: KdlNode, v: var auto)

proc decodeHook*[T: Value](a: KdlVal, v: var T)
proc decodeHook*[T: enum](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var char)
proc decodeHook*(a: KdlVal, v: var cstring)
proc decodeHook*[T: array](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var seq)
proc decodeHook*(a: KdlVal, v: var ref)
proc decodeHook*(a: KdlVal, v: var Object)

# ----- Hooks -----

proc newHook*(v: var auto) = 
  type T = typeof(v)
  when v is range:
    if v notin T.low..T.high:
      v = T.low

proc postHook*(v: var auto) = 
  discard

proc enumHook*[T: enum](a: int, v: var T) = 
  when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
    fail &"forbidden int-to-HoleyEnum conversion ({a} -> {$T}); compile with -d:kdlDecoderAllowHoleyEnums"
  else:
    v = T(a)

proc enumHook*[T: enum](a: string, v: var T) = 
  v = parseEnum[T](a)

proc renameHook*(_: typedesc, fieldName: var string) = 
  discard

proc newHookable*(v: var auto) = 
  when not defined(kdlDecoderNoCaseTransitionError):
    {.push warningAsError[CaseTransition]: on.}
  mixin newHook
  newHook(v)

proc postHookable*(v: var auto) = 
  mixin postHook
  postHook(v)

proc enumHookable*[T: enum](a: string or int, v: var T) = 
  mixin enumHook
  enumHook(a, v)

proc renameHookable*(fieldName: string, a: typedesc): string = 
  mixin renameHook
  result = fieldName
  renameHook(a, result)

# ----- KdlSome -----

proc decode*(a: KdlSome, v: var auto) = 
  mixin decodeHook

  # Don't initialize object variants yet
  when not isObjVariant(typeof v):
    newHookable(v)

  decodeHook(a, v)

proc decode*[T](a: KdlSome, _: typedesc[T]): T = 
  decode(a, result)

proc decode*(a: KdlDoc, v: var auto, name: string) = 
  var found = -1
  for e in countdown(a.high, 0):
    if a[e].name.eqIdent name:
      found = e
      break

  if found < 0:
    fail "Could not find a any node for " & name.quoted

  decode(a[found], v)

proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T = 
  decode(a, result, name)

proc decodeHook*[T: KdlSome](a: T, v: var T) = 
  v = a

proc decodeHook*(a: KdlSome, v: var proc) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

# ----- KdlDoc -----

proc decodeHook*(a: KdlDoc, v: var Object) = 
  type T = typeof(v)
  const discKeys = getDiscriminants(T) # Object variant discriminator keys

  when discKeys.len > 0:
    template discriminatorSetter(key, typ): untyped = 
      let discFieldNode = a.rfind(key.renameHookable(T))

      if discFieldNode.isSome:
        decode(discFieldNode.get, typ)
      else:
        var x: typeofdesc typ
        newHookable(x)
        x

    v = initCaseObject(T, discriminatorSetter)
    newHookable(v)

  for fieldName, field in v.fieldPairs:
    when fieldName notin discKeys: # Ignore discriminant field name
      var found = false

      for node in a:
        if node.name.renameHookable(T).eqIdent fieldName:
          decode(node, field)
          found = true

      if not found:
        newHookable(field)

  postHookable(v)

proc decodeHook*(a: KdlDoc, v: var ref) = 
  decode(a, v[])

proc decodeHook*(a: KdlDoc, v: var List) = 
  when v is seq:
    v.setLen a.len
  
  for e, node in a:
    decode(node, v[e])

  postHookable(v)

# ----- KdlNode -----

proc decodeHook*(a: KdlNode, v: var Object) = 
  type T = typeof(v)
  const discKeys = getDiscriminants(T) # Object variant discriminator keys

  when discKeys.len > 0:
    template discriminatorSetter(key, typ): untyped = 
      let key1 = key.renameHookable(T)
      let discFieldNode = a.children.rfind(key1) # Find a children
      let discFieldProp = a.find(key1) # Find a property

      if discFieldNode.isSome:
        decode(discFieldNode.get, typ)
      elif discFieldProp.isSome:
        decode(discFieldProp.get, typ)
      else:
        var x: typeofdesc typ
        newHookable(x)
        x

    v = initCaseObject(T, discriminatorSetter)
    newHookable(v)

  for fieldName, field in v.fieldPairs:
    when fieldName notin discKeys: # Ignore discriminant field name
      var found = false
      for key, _ in a.props:
        if key.renameHookable(T).eqIdent fieldName:
          decode(a.props[key], field)
          found = true

      for node in a.children:
        if node.name.renameHookable(T).eqIdent fieldName:
          decode(node, field)
          found = true

      if not found:
        newHookable(field)

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var ref) = 
  decode(a, v[])

proc decodeHook*(a: KdlNode, v: var List) = 
  when v is seq:
    v.setLen a.args.len + a.children.len

  var count = 0

  for arg in a.args:
    if count >= v.len: break
    decode(arg, v[count])

    inc count

  for child in a.children:
    if count >= v.len: break
    decode(child, v[count])
    inc count

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var auto) = 
  check a.args.len == 1, &"expect exactly one argument in {a}"
  decode(a.args[0], v)

# ----- KdlVal -----

proc decodeHook*[T: Value](a: KdlVal, v: var T) = 
  v = a.get(T)
  postHookable(v)

proc decodeHook*[T: enum](a: KdlVal, v: var T) = 
  case a.kind
  of KString:
    enumHookable(a.getString, v)
  of KInt:
    enumHookable(a.get(int), v)

  else:
    fail &"expected string or int in {a}"

  postHookable(v)

proc decodeHook*(a: KdlVal, v: var char) = 
  check a.isString and a.getString.len == 1, &"expected one-character-long string in a"
  v = a.getString[0]
  postHookable(v)

proc decodeHook*(a: KdlVal, v: var cstring) = 
  case a.kind
  of KNull:
    v = nil
  of KString:
    v = cstring a.getString
  else: 
    fail &"expected string or null in {a}"
  postHookable(v)

proc decodeHook*[T: array](a: KdlVal, v: var T) = 
  when v.len == 1:
    decode(a, v[0])

proc decodeHook*(a: KdlVal, v: var seq) = 
  v.setLen 1
  decode(a, v[0])

proc decodeHook*(a: KdlVal, v: var ref) = 
  decode(a, v[])

proc decodeHook*(a: KdlVal, v: var Object) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

# ----- Non-primitive stdlib hooks -----

# ----- Index -----

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T])

proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlNode, v: var SomeSet[T])
proc decodeHook*(a: KdlNode, v: var StringTableRef)
proc decodeHook*[T](a: KdlNode, v: var Option[T])

proc decodeHook*[T](a: KdlVal, v: var SomeSet[T])
proc decodeHook*[T](a: KdlVal, v: var Option[T])
proc decodeHook*(a: KdlVal, v: var (SomeTable[string, auto] or StringTableRef))

# ----- KdlDoc -----

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T]) = 
  v.clear()

  for node in a:
    v[node.name] = decode(node, T)

  postHookable(v)

proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T]) = 
  v.clear()

  for node in a:
    v.incl decode(KdlDoc, T)

  postHookable(v)

# ----- KdlNode -----

proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T]) = 
  v.clear()

  for key, val in a.props:
    v[key] = decode(val, T)
    
  for node in a.children:
    v[node.name] = decode(node, T)

  postHookable(v)

proc decodeHook*[T](a: KdlNode, v: var SomeSet[T]) = 
  v.clear()

  for arg in a.args:
    v.incl decode(arg, T)

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var StringTableRef) = 
  v = newStringTable()

  for key, val in a.props:
    v[key] = decode(val, string)
    
  for node in a.children:
    v[node.name] = decode(node, string)

  postHookable(v)

proc decodeHook*[T](a: KdlNode, v: var Option[T]) = 
  v = 
    try:  
      decode(a, T).some
    except KdlError:
      none[T]()

  postHookable(v)

# ----- KdlVal -----

proc decodeHook*[T](a: KdlVal, v: var SomeSet[T]) = 
  v.clear()

  v.incl decode(a, T)

  postHookable(v)

proc decodeHook*[T](a: KdlVal, v: var Option[T]) = 
  if a.isNull:  
    v = none[T]()
  else:
    v = decode(a, T).some

  postHookable(v)

proc decodeHook*(a: KdlVal, v: var (SomeTable[string, auto] or StringTableRef)) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"
