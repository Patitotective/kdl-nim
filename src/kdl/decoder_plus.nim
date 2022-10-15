import std/[strformat, strtabs, tables, sets]
import decoder, nodes, utils, types

# ----- Index -----

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T])
proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlNode, v: var SomeSet[T])
proc decodeHook*(a: KdlNode, v: var StringTableRef)
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
