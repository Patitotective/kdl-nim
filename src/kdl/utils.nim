## Various utilities for internal use in the library.
import std/[strformat, strutils, unicode, streams, tables, macros, sets]

import types

type
  Coord* = object
    line*, idx*: int
    col*: int # col counts each unicode character (rune) as one
    colNonAscii*: int # number of non ascii (unicode chars) until col
    # this is a weird way of dealing with non-fixed width characters until an apporach
    # lice rust's unicode-width appears...

  Object* = (
    (object or tuple) and not KdlSome and not SomeTable and not List and not Value and
    not SomeSet
  )
  List* = (array or seq)
  Value* = (SomeNumber or string or bool) #  or range
  KdlSome* = (KdlDoc or KdlNode or KdlVal)
  SomeTable*[K, V] = (Table[K, V] or OrderedTable[K, V])

const
  newLines* = ["\c\l", "\r", "\n", "\u0085", "\f", "\u2028", "\u2029"]
  escapeTable* = {
    'n': "\u000A", # Line Feed
    'r': "\u000D", # Carriage Return
    't': "\u0009", # Character Tabulation (Tab)
    '\\': "\u005C", # Reverse Solidus (Backslash)
    '/': "\u002F", # Solidus (Forwardslash)
    '"': "\u0022", # Quotation Mark (Double Quote)
    'b': "\u0008", # Backspace
    'f': "\u000C", # Form Feed
  }.toTable

template fail*(msg: string) =
  raise newException(KdlError, msg)

template check*(cond: untyped, msg = "") =
  if not cond:
    let txt = msg
    fail astToStr(cond) & " failed" & (if txt.len > 0: ": " & txt else: "")

proc `$`*(c: Coord): string =
  &"{c.line+1}:{c.col+1}"

proc quoted*(x: string): string =
  result.add '"'
  var i = 0
  while i < x.len:
    var isEscape = false
    for k, v in escapeTable:
      # Don't escape forward slash
      if k != '/' and x.continuesWith(v, i):
        result.add &"\\{k}"
        i.inc v.len
        isEscape = true
    if not isEscape:
      result.add x[i]
      i.inc
  result.add '"'

proc cmpIgnoreStyle(a, b: openarray[char], ignoreChars = {'_', '-'}): int =
  let aLen = a.len
  let bLen = b.len
  var i = 0
  var j = 0

  while true:
    while i < aLen and a[i] in ignoreChars:
      inc i
    while j < bLen and b[j] in ignoreChars:
      inc j
    let aa =
      if i < aLen:
        toLowerAscii(a[i])
      else:
        '\0'
    let bb =
      if j < bLen:
        toLowerAscii(b[j])
      else:
        '\0'
    result = ord(aa) - ord(bb)
    if result != 0:
      return result
    # the characters are identical:
    if i >= aLen:
      # both cursors at the end:
      if j >= bLen:
        return 0
      # not yet at the end of 'b':
      return -1
    elif j >= bLen:
      return 1
    inc i
    inc j

proc eqIdent*(v, a: openarray[char], ignoreChars = {'_', '-'}): bool =
  cmpIgnoreStyle(v, a, ignoreChars) == 0

# ----- Streams -----

proc peekRune*(s: Stream): Rune =
  let str = s.peekStr(4)
  if str.len > 0:
    result = str.runeAt(0)

proc peekLineFromStart*(s: Stream): string =
  let before = s.getPosition()
  while s.getPosition() > 0:
    s.setPosition(s.getPosition() - 1)
    if s.peekChar() in Newlines:
      s.setPosition(s.getPosition() + 1)
      if s.atEnd:
        s.setPosition(s.getPosition() - 1)

      break

  result = s.peekLine()
  s.setPosition before

proc peekLineFromStart*(s: string, at: int): string =
  let at = if at >= s.len: s.high else: at

  var idx = 0
  for i in countdown(at - 1, 0):
    if s[i] in Newlines:
      idx = i + 1
      if idx == s.high:
        dec idx
      break

  for i in idx .. s.high:
    if s[i] in Newlines:
      return s[idx ..< i]

  result = s[idx ..^ 1]

## colNonAscii is the number of colNonAscii unicode chars in the input
proc getCoord*(s: Stream, i: int): Coord =
  let before = s.getPosition()
  s.setPosition 0
  while s.getPosition() < i:
    var isNewLine = false
    for n in newlines:
      if (let str = s.peekStr(n.len); str == n):
        inc result.line
        result.col = 0
        result.colNonAscii = 0
        result.idx.inc n.len
        isNewLine = true
        s.setPosition(s.getPosition() + n.len)

    if not isNewLine:
      let r = s.peekRune()
      inc result.col
      result.idx.inc r.size
      if r.size > 1:
        inc result.colNonAscii
      s.setPosition(s.getPosition() + r.size)

  s.setPosition before

proc getCoord*(s: string, at: int): Coord =
  var i, col = 0
  while i < at:
    var isNewLine = false
    for n in newLines:
      if s.continuesWith(n, i):
        inc result.line
        i.inc n.len
        result.colNonAscii = 0
        result.col = 0
        isNewLine = true

    if not isNewLine:
      let r = s.runeAt(i)
      i.inc r.size
      inc result.col
      if r.size > 1:
        inc result.colNonAscii

  result.idx = i

proc isDisallowedRune*(r: Rune or int32): bool =
  when r is Rune:
    let r = r.int32
  else:
    let r = r

  r in 0xD800i32 .. 0xDFFFi32 or r in 0x0000i32 .. 0x0008i32 or
    r in 0x000Ei32 .. 0x001Fi32 or r == 0x007Fi32 or r in 0x200Ei32 .. 0x200Fi32 or
    r in 0x202A .. 0x202Ei32 or r in 0x2066i32 .. 0x2069i32

proc escapeRunes(s: string, until: int): tuple[s: string, extraLen: int] =
  ## Escapes all disallowed runes in s with their unicode code and returns the escaped
  ## string as well as the difference in length between the escaped string and the 
  ## original string until until
  var e = 0
  for r in s.runes:
    if r.int32 == 0xFEFFi32 or r.isDisallowedRune():
      let escaped = &"<{r.int32.toHex(4).toLowerAscii}>"
      result.s.add escaped
      if e < until:
        result.extraLen.inc escaped.len - 1
    else:
      result.s.add r

    e.inc

proc errorAt*(s: Stream or string, coord: Coord): string =
  when s is Stream:
    let before = s.getPosition()
    s.setPosition coord.idx
    var line = s.peekLineFromStart()
    s.setPosition before
  else:
    var line = s.peekLineFromStart(coord.idx)

  var extraLen: int
  (line, extraLen) = line.escapeRunes(coord.col)

  let lineNum = &"{coord.line + 1} | "
  result.add &"{lineNum}{line}\n"
  result.add align("^", lineNum.len + coord.col + extraLen + coord.colNonAscii)

# ----- Object variants -----

macro isObjVariant*(a: typedesc): bool =
  var a = a.getTypeImpl
  if a.kind != nnkBracketExpr:
    return ident("false")

  let sym = a[1]
  let t = sym.getTypeImpl
  if t.kind != nnkObjectTy:
    return ident("false")

  let t2 = t[2]
  if t2.kind != nnkRecList:
    return ident("false")

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
  if a.kind != nnkBracketExpr:
    return quote:
      newSeq[string]()

  let sym = a[1]
  let t = sym.getTypeImpl
  if t.kind != nnkObjectTy:
    return quote:
      newSeq[string]()

  let t2 = t[2]
  if t2.kind != nnkRecList:
    return quote:
      newSeq[string]()

  result = newTree(nnkBracket)

  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      result.add newLit key.strVal

  result =
    if result.len > 0:
      quote:
        @`result`
    else:
      quote:
        newSeq[string]()

macro initCaseObject*(T: typedesc, discriminatorSetter): untyped =
  ## Does the minimum to construct a valid case object `T`.
  ## - `discriminatorSetter`: called passing two arguments `(key, typ)` (`key` being the field name and `typ` the field type), last expression should be the value for the field. Only for discriminator fields.
  # maybe candidate for std/typetraits

  var a = T.getTypeImpl

  doAssert a.kind == nnkBracketExpr

  let sym = a[1]
  let t = sym.getTypeImpl
  var t2: NimNode

  case t.kind
  of nnkObjectTy:
    t2 = t[2]
  of nnkRefTy:
    t2 = t[0].getTypeImpl[2]
  else:
    doAssert false, $t.kind
    # xxx `nnkPtrTy` could be handled too

  doAssert t2.kind == nnkRecList

  result = newTree(nnkObjConstr)
  result.add sym

  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      let key2 = key.strVal
      let val = quote:
        `discriminatorSetter`(`key2`, typedesc[`typ`])

      result.add newTree(nnkExprColonExpr, key, val)

template typeofdesc*[T](b: typedesc[T]): untyped =
  T
