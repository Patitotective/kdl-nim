import std/[sequtils, tables]
import nodes, utils

type
  Value = SomeNumber or string or bool
  Object = object or tuple

func normalize(s: string): string =
  ## COnverts s to lower case and removes any hyphen(-) or underscore(_).
  result = newString(s.len)
  if s.len > 0:
    result[0] = s[0]
  var j = 1
  for i in 1..len(s) - 1:
    if s[i] in {'A'..'Z'}:
      result[j] = chr(ord(s[i]) + (ord('a') - ord('A')))
      inc j
    elif s[i] notin {'_', '-'}:
      result[j] = s[i]
      inc j
  if j != s.len: setLen(result, j)

func eqIdent(a, b: string): bool = normalize(a) == normalize(b)

proc decode*[T: Value](val: KdlVal, x: var T) = 
  x = val.get(T)

proc decode*[T: Value](node: KdlNode, x: var T) = 
  assert node.len == 1, "expected exactly one argument; got " & $node.len
  node[0].decode(x)

proc decode*[T: Value](node: KdlNode, x: var seq[T]) = 
  x.setLen(node.len)
  for e, arg in node.args:
    arg.decode(x[e])

proc decode*[T: Value](val: KdlVal, x: var Option[T]) = 
  try:
    x = val.decode(T).some()
  except:
    discard

proc decode*[T: Value](node: KdlNode, x: var Option[T]) = 
  try:
    x = node.decode(T).some
  except:
    discard

proc decode*[T](doc: KdlDoc, x: var Table[string, T]) = 
  for node in doc:
    x[node.name] = node.decode(T)

proc decode*[T](node: KdlNode, x: var Table[string, T]) = 
  for key, val in node.props:
    x[key] = val.decode(T)

  node.children.decode(x)

proc decode*[T: Object](node: KdlNode, x: var T) = 
  for field, val in x.fieldPairs:
    when val is Value:
      var name: string
      if (block x:
        var result = false
        for key, _ in node.props:
          if key.eqIdent field:
            name = key
            result = true
            break x
        not result):
        when defined(kdlDecodingNameNotFoundError):
          raise newException(ValueError, "Could not find a any node for the " & field.quoted & " field")
      else:
        try:
          node[name].decode(val)
        except Exception as error:
          error.msg.add " in " & field.quoted
          raise

  node.children.decode(x)

proc decode*[T: Object](doc: KdlDoc, x: var T) = 
  for field, val in x.fieldPairs:
    let nodes = doc.filterIt(it.name.eqIdent field)
    if nodes.len == 0:
      when defined(kdlDecodingNameNotFoundError):
        raise newException(ValueError, "Could not find a any node for the " & field.quoted & " field")
    else:
      for node in nodes:
        try:
          node.decode(val)
        except Exception as error:
          error.msg.add " in " & field.quoted
          raise

proc decode*[T: Object](doc: KdlDoc, x: var seq[T]) = 
  x.setLen(doc.len)
  for e, node in doc:
    x.add node.children.decode(T)

proc decode*[A: KdlDoc or KdlVal or KdlNode, B](obj: A, z: typedesc[B]): B = 
  obj.decode(result)

proc decode*[T](doc: KdlDoc, x: var T, name: string) = 
  let nodes = doc.filterIt(it.name.eqIdent name)
  if nodes.len == 0:
    raise newException(ValueError, "Could not find a any node for " & name.quoted)

  nodes[^1].decode(x)

proc decode*[T](doc: KdlDoc, x: typedesc[T], name: string): T = 
  doc.decode(result, name)
