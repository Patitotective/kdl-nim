import std/[strformat, strutils, unicode, streams, tables, macros]

import types

type
  Coord* = object
    line*, col*, idx*: int

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

# ----- Streams -----

proc getPos*(s: Stream): int = 
  s.getPosition()

proc setPos*(s: Stream, x: int) = 
  s.setPosition(x)

proc inc*(s: Stream, x = 1) = 
  s.setPos(s.getPos() + x)

proc dec*(s: Stream, x = 1) = 
  s.setPos(s.getPos() - x)

proc peekRune*(s: Stream): Rune = 
  let str = s.peekStr(4)
  if str.len > 0:
    result = str.runeAt(0)

proc peekLineFromStart*(s: Stream): string = 
  let before = s.getPos()
  while s.getPos() > 0:
    dec s
    if s.peekChar() == '\n':
      inc s
      if s.atEnd: dec s
      break

  result = s.peekLine()
  s.setPos before

proc getCoord*(s: Stream, i: int): Coord =
  let before = s.getPos()
  s.setPos 0
  while s.getPos() < i:
    if (let str = s.peekStr(2); str == "\c\l" or str[0] == '\n'):
      inc result.line
      result.col = 0
    else:
      inc result.col

    inc s
    inc result.idx

  s.setPos before

proc errorAt*(s: Stream, coord: Coord): string = 
  let before = s.getPos()
  s.setPos coord.idx
  let line = s.peekLineFromStart()
  s.setPos before

  let lineNum = &"{coord.line + 1} | "
  result.add(&"{lineNum}{line}\n")
  result.add(&"{repeat(' ', lineNum.len + coord.col)}^")

# ----- Object variants -----

macro isObjVariant*(a: typedesc): bool = 
  var a = a.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  if t.kind != nnkObjectTy:
    return ident("false")

  let t2 = t[2]
  doAssert t2.kind == nnkRecList

  result = ident("false")

  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]

      return ident("true")

macro getDiscriminants*(a: typedesc): seq[string] =
  ## return the discriminant keys
  # candidate for std/typetraits
  var a = a.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  if t.kind != nnkObjectTy:
    return quote do:
      newSeq[string]()

  let t2 = t[2]
  doAssert t2.kind == nnkRecList
  result = newTree(nnkBracket)

  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      result.add newLit key.strVal
  
  result = 
    if result.len > 0:
      quote do:
        @`result`
    else:
      quote do:
        newSeq[string]()

macro initCaseObject*(T: typedesc, discriminatorSetter): untyped =
  ## Does the minimum to construct a valid case object `T`.
  ## - `discriminatorSetter`: called passing two arguments `(key, typ)` (`key` being the field name and `typ` the field type), last expression should be the value for the field
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

# let s = newStringStream("\nabc\n")
# s.setPos 4
# echo s.peekLineFromStart()
