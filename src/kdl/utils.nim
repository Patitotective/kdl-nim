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

template error*(msg: string) = 
  raise newException(KdlError, msg)

template check*(cond: untyped, msg = "") = 
  if not cond:
    let txt = msg
    utils.error astToStr(cond) & " failed" & (if txt.len > 0: ": " & txt else: "")

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

proc `[]`(node: NimNode, kind: NimNodeKind): NimNode =
  for c in node.children:
    if c.kind == kind:
      return c
  return nil

proc hasKind(node: NimNode, kind: NimNodeKind): bool =
  for c in node.children:
    if c.kind == kind:
      return true
  return false

macro isObjVariant*(v: typed): bool =
  ## Is this an object variant?
  var typ = v.getTypeImpl()
  if typ.kind == nnkSym:
    return ident("false")
  while typ.kind != nnkObjectTy:
    typ = typ[0].getTypeImpl()
  if typ[2].hasKind(nnkRecCase):
    ident("true")
  else:
    ident("false")

proc discriminator*(v: NimNode): NimNode =
  var typ = v.getTypeImpl()
  while typ.kind != nnkObjectTy:
    typ = typ[0].getTypeImpl()
  return typ[nnkRecList][nnkRecCase][nnkIdentDefs][nnkSym]

macro discriminatorFieldName*(v: typed): untyped =
  ## Turns into the discriminator field.
  return newLit($discriminator(v))

macro discriminatorField*(v: typed): untyped =
  ## Turns into the discriminator field.
  let
    fieldName = discriminator(v)
  return quote do:
    `v`.`fieldName`

macro new*(v: typed, d: typed): untyped =
  ## Creates a new object variant with the discriminator field.
  let
    typ = v.getTypeInst()
    fieldName = discriminator(v)
  return quote do:
    `v` = `typ`(`fieldName`: `d`)
