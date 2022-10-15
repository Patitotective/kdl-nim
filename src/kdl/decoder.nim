import std/[strformat, typetraits, strutils, strtabs, tables, sets]
import nodes, utils, types

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

proc decodeHook*(a: KdlSome, v: var proc) = 
  error &"{$typeof(v)} not implemented for {$typeof(a)}"

# ----- KdlDoc -----

proc decodeHook*(a: KdlDoc, v: var Object) = 
  when v.isObjVariant:
    # Object variant discriminator
    const discFieldName = discriminatorFieldName(v)
    var
      discField = discriminatorField(v)
      discFieldNode: Option[KdlNode]

    for node in a:
      if node.name.eqIdent discFieldName:
        discFieldNode = node.some

    if discFieldNode.isSome:
      new(v, decode(discFieldNode.get, typeof discField))
    else:
      error &"Could not find discriminant field for {$typeof(v)} in {a}"

  for fieldName, field in v.fieldPairs:
    when not v.isObjVariant or fieldName != discFieldName: # Ignore discriminant field name
      for node in a:
        if node.name.eqIdent fieldName:
          decode(node, field)

proc decodeHook*(a: KdlDoc, v: var ref) = 
  decode(a, v[])

proc decodeHook*(a: KdlDoc, v: var List) = 
  when v is seq:
    v.setLen a.len
  
  for e, node in a:
    decode(node, v[e])

# ----- KdlNode -----

proc decodeHook*(a: KdlNode, v: var Object) = 
  when v.isObjVariant:
    # Object variant discriminator
    const discFieldName = discriminatorFieldName(v)
    var
      discField = discriminatorField(v)
      discFieldNode: Option[KdlNode]
      discFieldVal: Option[KdlVal]

    for key, val in a.props:
      if key.eqIdent discFieldName:
        discFieldVal = val.some
 
    for node in a.children:
      if node.name.eqIdent discFieldName:
        discFieldNode = node.some

    if discFieldNode.isSome:
      new(v, decode(discFieldNode.get, typeof discField))
    elif discFieldVal.isSome:
      new(v, decode(discFieldVal.get, typeof discField))
    else:
      error &"Could not find discriminant field for {$typeof(v)} in {a}"

  for fieldName, field in v.fieldPairs:
    when not v.isObjVariant or fieldName != discFieldName: # Ignore discriminant field name
      for key, _ in a.props:
        if key.eqIdent fieldName:
          decode(a.props[key], field)
    
      for node in a.children:
        if node.name.eqIdent fieldName:
          decode(node, field)

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

proc decodeHook*(a: KdlVal, v: var ref) = 
  decode(a, v[])

proc decodeHook*(a: KdlVal, v: var Object) = 
  error &"{$typeof(v)} not implemented for {$typeof(a)}"


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

proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T]) = 
  v.clear()

  for node in a:
    v.incl decode(KdlDoc, T)

# ----- KdlNode -----

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

proc decodeHook*[T](a: KdlNode, v: var Option[T]) = 
  v = 
    try:  
      decode(a, T).some
    except KdlError:
      none[T]()

# ----- KdlVal -----

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
