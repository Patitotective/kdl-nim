{.used.}

import std/[strformat, typetraits, strutils, strtabs, tables, sets]
import nodes, utils, types

type
  SomeTable[A, B] = (Table[A, B] or OrderedTable[A, B])
  KdlSome = (KdlDoc or KdlNode or KdlVal)
  Object = ((object or tuple) and not KdlSome)

proc cmpIgnoreStyle(a, b: openarray[char]): int =
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

proc eqIdent(a, b: openarray[char]): bool = cmpIgnoreStyle(a, b) == 0

proc decode*[T](a: var T, b: KdlVal)
proc decode*[T](a: var T, b: KdlNode)
proc decode*[T](a: var T, b: KdlDoc)

proc decode*[T](a: var T, b: KdlDoc) = 
  when compiles(decodeHook(a, b)): decodeHook(a, b)
  elif T is Object:
    for field, value in a.fieldPairs:
      for node in b:
        if node.name.eqIdent field:
          decode(value, node)   
  elif T is (array or seq):
    when T is seq:
      a.setLen b.len
  
    for e, node in b:
      decode(a[e], node)
  else:
    static: error &"{$T} not implemented yet for {$typeof(b)}"

proc decode*[T](a: var T, b: KdlNode) = 
  # static: echo T, ", ", typeof b

  when compiles(decodeHook(a, b)): decodeHook(a, b)
  elif T is Object:
    for field, value in a.fieldPairs:
      for key, _ in b.props:
        if key.eqIdent field:
          when compiles(decode(value, b.props[key])):
            decode(value, b.props[key])
      
      for node in b.children:
        if node.name.eqIdent field:
          decode(value, node)
  elif T is (array or seq):
    when T is seq:
      a.setLen b.args.len + b.children.len

    var count = 0

    for arg in b.args:
      if count >= a.len: break
      when compiles(decode(a[count], arg)):
        decode(a[count], arg)

      inc count

    for child in b.children:
      if count >= a.len: break
      decode(a[count], child)
      inc count
  else:
    check b.args.len == 1, &"expect exactly one argument in {b}"
    decode(a, b.args[0])

proc decode*[T](a: var T, b: KdlVal) = 
  when compiles(decodeHook(a, b)): decodeHook(a, b)
  elif T is KdlVal:
    a = b
  elif T is (SomeNumber or string or bool):
    a = b.get(T)
  elif T is enum:
    case b.kind
    of KString:
      a = parseEnum[T](b.getString)
    of KInt:
      when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
        error &"forbidden int-to-HoleyEnum conversion ({b.getInt} -> {$T}); compile with -d:kdlDecoderAllowHoleyEnums"
      else:
        a = T(b.getInt)
    else:
      error &"expected string or int in {b}"
  elif T is cstring:
    case b.kind
    of KNull:
      a = nil
    of KString:
      a = cstring b.getString
    else: 
      error &"expected string or null in {b}"
  elif T is array:
    when a.len == 1:
      decode(a[0], b)
  elif T is seq:
    a.setLen 1
    decode(a[0], b)
  elif T is char:
    check b.isString, &"expected one-character-long string in b"
    a = b.getString[0]
  else:
    static: error &"{$T} not implemented yet for {$typeof(b)}"

proc decode*[T](a: var T, b: KdlDoc, name: string) = 
  var found = -1
  for e in countdown(b.high, 0):
    if b[e].name.eqIdent name:
      found = e
      break

  if found < 0:
    error &"Could not find a any node for {name}"

  decode(a, b[found])

proc decode*[T: KdlSome](a: var T, b: T) = 
  a = T

proc decode*[T](a: KdlSome, b: typedesc[T]): T = 
  ## Outplace version of `decode`.
  decode(result, a)

proc decode*[T](a: KdlSome, b: typedesc[T], name: string): T = 
  ## Outplace version of `decode`.
  decode(result, a, name)

proc decodeHook*[T](a: var SomeTable[string, T], b: KdlDoc) = 
  a.clear()

  for node in b:
    a[node.name] = decode(node, T)

proc decodeHook*[T](a: var SomeTable[string, T], b: KdlNode) = 
  a.clear()

  for key, val in b.props:
    a[key] = decode(val, T)
  
  for node in b.children:
    a[node.name] = decode(node, T)

# proc decodeHook*[T](a: var SomeTable[string, SomeTable[string, T]], b: KdlNode) = 
  # discard

proc decodeHook*[T](a: var SomeSet[T], b: KdlNode) = 
  a.clear()

  for arg in b.args:
    a.incl decode(arg, T)

  for child in b.children:
    a.incl decode(child, T)

proc decodeHook*[T](a: var Option[T], b: KdlVal) = 
  if b.isNull:
    a = none[T]()
  else:
    a = 
      try:
        decode(b, T).some
      except KdlError:
        none[T]()

proc decodeHook*[T](a: var Option[T], b: KdlNode) = 
  a = 
    try:
      decode(b, T).some
    except KdlError:
      none[T]()

proc decodeHook*(a: var StringTableRef, b: KdlNode) = 
  a = newStringTable()

  for key, val in b.props:
    a[key] = decode(val, string)
  
  for node in b.children:
    a[node.name] = decode(node, string)

const node = toKdlNode:
  person:
    age(now="10", before="9")
    name(actual="Phil", other="Isofruit")

var table: Table[string, Table[string, string]]

decode(table, node)

echo table
