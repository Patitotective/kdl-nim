import std/[strformat, strutils, tables, macros]

import types

type
  Coord* = object
    line*, col*: int

  Object* = ((object or tuple) and not KdlSome)
  List* = (array or seq)
  Value* = (SomeNumber or string or bool)
  KdlSome* = (KdlDoc or KdlNode or KdlVal)
  SomeTable*[K, V] = (Table[K, V] or OrderedTable[K, V])

template fail*(msg: string) = 
  raise newException(KdlError, msg)

template check*(cond: untyped, msg = "") = 
  if not cond:
    let txt = msg
    fail astToStr(cond) & " failed" & (if txt.len > 0: ": " & txt else: "")

proc quoted*(x: string): string = result.addQuoted(x)
  
proc getCoord*(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result.line = lines.high
  result.col = lines[^1].len

proc errorAt*(source: string, coord: Coord): string = 
  let line = source.splitLines[coord.line]

  let lineNum = &"{coord.line + 1} | "
  result.add(&"{lineNum}{line}\n")
  result.add(&"{repeat(' ', lineNum.len + coord.col)}^\n")

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

proc eqIdent*(v, a: openarray[char], ignoreChars = {'_', '-'}): bool = cmpIgnoreStyle(v, a, ignoreChars) == 0

# ----- Object variants -----

macro getDiscriminants*(a: typedesc): seq[string] =
  ## return the discriminant keys
  # candidate for std/typetraits
  var a = a.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  let t2 = t[2]
  doAssert t2.kind == nnkRecList
  result = newTree(nnkBracket)
  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      result.add newLit key.strVal
  if result.len > 0:
    result = quote do:
      @`result`
  else:
    result = quote do:
      seq[string].default

macro initCaseObject*(T: typedesc, discriminatorSetter: untyped): untyped =
  ## does the minimum to construct a valid case object, only initializing
  ## calls `discriminatorSetter(key, typ)` expecting it to return that field's value (`key` being the field name and `typ` the field type)
  ## the discriminant fields; see also `getDiscriminants`
  # maybe candidate for std/typetraits
  var a = T.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  var t2: NimNode
  case t.kind
  of nnkObjectTy: t2 = t[2]
  of nnkRefTy: t2 = t[0].getTypeImpl[2]
  else: doAssert false, $t.kind # xxx `nnkPtrTy` could be handled too
  doAssert t2.kind == nnkRecList
  result = newTree(nnkObjConstr)
  result.add sym
  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      let key2 = key.strVal
      let val = quote do:
        `discriminatorSetter`(`key2`, typedesc[`typ`])
      result.add newTree(nnkExprColonExpr, key, val)

template typeofdesc*[T](b: typedesc[T]): untyped = T
