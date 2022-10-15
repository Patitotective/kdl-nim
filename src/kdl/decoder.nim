import std/[strformat, typetraits, strutils]
import nodes, utils, types

# ----- Index -----

proc decode*(a: KdlSome, v: var auto)
proc decode*[T](a: KdlSome, _: typedesc[T]): T

proc decode*(a: KdlDoc, v: var auto, name: string)
proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T

proc decodeHook*[T: KdlSome](a: T, v: var T)

proc decodeHook*(a: KdlDoc, v: var Object)
proc decodeHook*(a: KdlDoc, v: var List)

proc decodeHook*(a: KdlNode, v: var Object)
proc decodeHook*(a: KdlNode, v: var List)
proc decodeHook*(a: KdlNode, v: var auto)

proc decodeHook*[T: Value](a: KdlVal, v: var T)
proc decodeHook*[T: enum](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var char)
proc decodeHook*(a: KdlVal, v: var cstring)
proc decodeHook*[T: array](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var seq)

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

proc decodeHook*[T: KdlSome](a: T, v: var T) = 
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

proc decodeHook*(a: KdlVal, v: var Object) = 
  error &"{$typeof(v)} not implemented for {$typeof(a)}"
