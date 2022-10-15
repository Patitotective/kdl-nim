{.used.}

import std/[strformat, typetraits, strutils, strtabs, tables, sets]
import nodes, utils, types

type
  Object = (object or tuple)
  List = (array or seq)
  Value = (SomeNumber or string or bool)
  KdlSome = (KdlDoc or KdlNode or KdlVal)
  SomeTable[K, V] = (Table[K, V] or OrderedTable[K, V])

proc cmpIgnoreStyle(a, b: openarray[char], ignoreChars = {'_', '-'}): int =
  let aLen = a.len
  let bLen = b.len
  var i = 0
  var j = 0

  while true:
    while i < aLen and a[i] in ignoreChars: inc i
    while j < bLen and b[j] in ignoreChars: inc j
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

proc eqIdent(v, a: openarray[char], ignoreChars = {'_', '-'}): bool = cmpIgnoreStyle(v, a, ignoreChars) == 0

# ----- KdlSome -----

proc decode*(a: KdlSome, v: var auto) = 
  mixin decodeHook
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
    error "Could not find a any node for " & name.quoted

  decode(a[found], v)

proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T = 
  decode(a, result, name)

# proc decodeKNode*(v: var auto): KdlNode = 
#   decode(result, v)

# proc decodeKVal*(v: var auto): KdlVal = 
#   decode(result, v)

proc decodeHook*[T: KdlNode or KdlVal](a: T, v: var T) = 
  v = a

# ----- KdlDoc -----

proc decodeHook*(a: KdlDoc, v: var Object) = 
  for field, value in v.fieldPairs:
    for node in a:
      if node.name.eqIdent field:
        decode(node, value)

proc decodeHook*(a: KdlDoc, v: var List) = 
  when v is seq:
    v.setLen a.len
  
  for e, node in a:
    decode(node, v[e])

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T]) = 
  v.clear()

  for node in a:
    v[node.name] = decode(node, T)

proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T]) = 
  v.clear()

  for node in a:
    v.incl decode(KdlDoc, T)

# ----- KdlNode -----

proc decodeHook*(a: KdlNode, v: var Object) = 
  for field, value in v.fieldPairs:
    for key, _ in a.props:
      if key.eqIdent field:
        decode(a.props[key], value)
    
    for node in a.children:
      if node.name.eqIdent field:
        decode(node, value)

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

proc decodeHook*(a: KdlNode, v: var auto) = 
  check a.args.len == 1, &"expect exactly one argument in {a}"
  decode(a.args[0], v)

proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T]) = 
  v.clear()

  for key, val in a.props:
    v[key] = decode(val, T)
    
  for node in a.children:
    v[node.name] = decode(node, T)

proc decodeHook*[T](a: KdlNode, v: var SomeSet[T]) = 
  v.clear()

  for arg in a.args:
    v.incl decode(arg, T)

proc decodeHook*(a: KdlNode, v: var StringTableRef) = 
  v = newStringTable()

  for key, val in a.props:
    v[key] = decode(val, string)
    
  for node in a.children:
    v[node.name] = decode(node, string)

# ----- KdlVal -----

proc decodeHook*[T: Value](a: KdlVal, v: var T) = 
  v = a.get(T)

proc decodeHook*[T: enum](a: KdlVal, v: var T) = 
  case a.kind
  of KString:
    v = parseEnum[T](a.getString)
  of KInt:
    when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
      error &"forbidden int-to-HoleyEnum conversion ({a.getInt} -> {$T}); compile with -d:kdlDecoderAllowHoleyEnums"
    else:
      v = T(a.getInt)
  else:
    error &"expected string or int in {a}"

proc decodeHook*(a: KdlVal, v: var char) = 
  check a.isString and a.getString.len == 1, &"expected one-character-long string in a"
  v = a.getString[0]

proc decodeHook*(a: KdlVal, v: var cstring) = 
  case a.kind
  of KNull:
    v = nil
  of KString:
    v = cstring a.getString
  else: 
    error &"expected string or null in {a}"

proc decodeHook*[T: array](a: KdlVal, v: var T) = 
  when v.len == 1:
    decode(a, v[0])

proc decodeHook*(a: KdlVal, v: var seq) = 
  v.setLen 1
  decode(a, v[0])

proc decodeHook*[T](a: KdlVal, v: var SomeSet[T]) = 
  v.clear()

  v.incl decode(a, T)

proc decodeHook*[T](a: KdlVal, v: var Option[T]) = 
  if a.isNull:  
    v = none[T]()
  else:
    v = decode(a, T).some

proc decodeHook*(a: KdlVal, v: var (SomeTable[string, auto] or StringTableRef)) = 
  error &"{$typeof(v)} not implemented for {$typeof(a)}"
