import std/tables
import nodes, utils

type
  Value = SomeNumber or string or bool

func toLowerAscii*(c: char): char {.inline.} =
  if c in {'A'..'Z'}:
    result = chr(ord(c) + (ord('a') - ord('A')))
  else:
    result = c

proc cmpIgnoreStyle*(a, b: openArray[char]): int =
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

proc eqIdent*(a, b: openArray[char]): bool = cmpIgnoreStyle(a, b) == 0

template error(msg: openArray[char]) = 
  raise newException(KdlError, msg)

template error(x: bool, msg: openArray[char]) = 
  if not x:
    error(msg)

proc decode*[T: Value](val: KdlVal, x: var T) = 
  x = val.get(T)

proc decode*[T: Value](node: KdlNode, x: var T) = 
  error node.len == 1, "expected exactly one argument; got " & $node.len
  node[0].decode(x)

proc decode*[T: Value](node: KdlNode, x: var seq[T]) = 
  x.setLen(node.len)
  for e, arg in node.args:
    arg.decode(x[e])

proc decode*[T: Value](val: KdlVal or KdlNode, x: var Option[T]) = 
  x = 
    try:
      node.decode(T).some
    except KdlError:
      T.none

proc decode*[T](doc: KdlDoc, x: var Table[string, T]) = 
  for node in doc:
    x[node.name] = node.decode(T)

proc decode*[T](node: KdlNode, x: var Table[string, T]) = 
  for key, val in node.props:
    x[key] = val.decode(T)

  node.children.decode(x)

proc decode*[T: object or tuple](node: KdlNode, x: var T) = 
  for field, val in x.fieldPairs:
    when val is Value:
      var found = false
      for key, _ in node.props:
        if key.eqIdent field:
          found = true
          
          try:
            node[key].decode(val)
          except KdlError as error:
            error.msg.add " in " & field.quoted
            raise

      when defined(kdlDecodingNameNotFoundError):
        if not found:
          raise newException(KdlError, "Could not find a any node for the " & field.quoted & " field")

  node.children.decode(x)

proc decode*[T: object or tuple](doc: KdlDoc, x: var T) = 
  for field, val in x.fieldPairs:
    var found = false
    for node in doc:
      if node.name.eqIdent field:
        found = true
        try:
          node.decode(val)
        except Exception as error:
          error.msg.add " in " & field.quoted
          raise

    when defined(kdlDecodingNameNotFoundError):
       if not found:
         raise newException(ValueError, "Could not find a any node for " & field.quoted)

proc decode*[T: object or tuple](doc: KdlDoc, x: var seq[T]) = 
  x.setLen(doc.len)
  for e, node in doc:
    x.add node.children.decode(T)

proc decode*[A: KdlDoc or KdlVal or KdlNode, B](obj: A, z: typedesc[B]): B = 
  obj.decode(result)

proc decode*[T](doc: KdlDoc, x: var T, name: openArray[char]) = 
  var found = -1
  for e in countdown(doc.high, 0):
    if doc[e].name.eqIdent name:
      found = e
      break

  if found < 0:
    error "Could not find a any node for " & name.quoted

  doc[found].decode(x)

proc decode*[T](doc: KdlDoc, x: typedesc[T], name: openArray[char]): T = 
  doc.decode(result, name)
