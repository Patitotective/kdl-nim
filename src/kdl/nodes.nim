import std/[strformat, options, tables, macros]

type
  KdlValKind* = enum
    KdlEmpty, 
    KdlString, 
    KdlFloat, 
    KdlBool, 
    KdlNull
    KdlInt, 

  KdlVal* = object
    tag*: Option[string] # Type tagation

    case kind*: KdlValKind
    of KdlString:
      str*: string
    of KdlFloat:
      fnum*: float
    of KdlBool:
      boolean*: bool
    of KdlInt:
      num*: int64
    of KdlEmpty, KdlNull:
      discard

  KdlProp* = tuple[key: string, val: KdlVal]

  KdlNode* = object
    tag*: Option[string]
    name*: string
    args*: seq[KdlVal]
    props*: Table[string, KdlVal]
    children*: seq[KdlNode]

  KdlDoc* = seq[KdlNode]

# ----- Initializers -----

proc initKNode*(name: string, tag = string.none, args: openArray[KdlVal] = newSeq[KdlVal](), props = initTable[string, KdlVal](), children: openArray[KdlNode] = newSeq[KdlNode]()): KdlNode = 
  KdlNode(tag: tag, name: name, args: @args, props: props, children: @children)

proc initKVal*(val: string, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KdlString, str: val)

proc initKVal*(val: float, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KdlFloat, fnum: val)

proc initKVal*(val: bool, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KdlBool, boolean: val)

proc initKVal*(val: int64, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KdlInt, num: val)

proc initKVal*(val: KdlVal): KdlVal = val

proc initKString*(val = string.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

proc initKFloat*(val = float64.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

proc initKBool*(val = bool.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

proc initKNull*(tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KdlNUll)

proc initKInt*(val = int64.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

# ----- Comparisions -----

proc isString*(val: KdlVal): bool = 
  val.kind == KdlString

proc isFloat*(val: KdlVal): bool = 
  val.kind == KdlFloat

proc isBool*(val: KdlVal): bool = 
  val.kind == KdlBool

proc isInt*(val: KdlVal): bool = 
  val.kind == KdlInt

proc isNull*(val: KdlVal): bool = 
  val.kind == KdlNull

proc isEmpty*(val: KdlVal): bool = 
  val.kind == KdlEmpty

# ----- Getters -----

proc getString*(val: KdlVal): string = 
  assert val.isString()
  val.str

proc getFloat*(val: KdlVal): float = 
  assert val.isFloat()
  val.fnum

proc getBool*(val: KdlVal): bool = 
  assert val.isBool()
  val.boolean

proc getInt*(val: KdlVal): int64 = 
  assert val.isInt()
  val.num

proc get*[T: SomeNumber or string or bool](val: KdlVal, x: typedesc[T]): T = 
  ## Tries to convert the value of val to T, raises an error when it cannot.
  runnableExamples:
    let val = initKInt(3.14)

    assert val.get(int) == 3
    assert val.get(uint) == 3u
    assert val.get(float) == 3.14
    assert val.get(float32) == 3.14f

  template error() = raise newException(ValueError, &"invalid type {$T} for {val.kind}")

  case val.kind
  of KdlString:
    when T is string:
      result = T(val.getString)
    else: error
  of KdlFloat:
    when T is SomeNumber:
      result = T(val.getFloat)
    else: error
  of KdlBool:
    when T is bool:
      result = T(val.getBool)
    else: error
  of KdlInt:
    when T is SomeNumber:
      result = T(val.getInt)
    else: error
  else: error

# ----- Extra -----

proc `[]`*(node: KdlNode, idx: int | BackwardsIndex): KdlVal = 
  ## Gets the argument at idx.
  node.args[idx]

proc `[]`*(node: KdlNode, key: string): KdlVal = 
  ## Gets the property value of key.
  node.props[key]

const identNodes = {nnkStrLit, nnkRStrLit, nnkTripleStrLit, nnkIdent}

proc strIdent(node: NimNode): NimNode = 
  node.expectKind(identNodes)
  newStrLitNode(node.strVal)

proc toKdlVal(body: NimNode): NimNode = 
  var tag = newCall("none", ident"string")
  var value = body

  if value.kind == nnkCall:
    value.expectLen(2)
    tag = newCall("some", value[1].strIdent)
    value = value[0]

  if value.kind == nnkNilLit:
    return newCall("initKNull", newTree(nnkExprEqExpr, ident"tag", tag))

  newCall("initKVal", value, newTree(nnkExprEqExpr, ident"tag", tag))

proc toKdlNodeImpl(body: NimNode): NimNode = 
  if body.kind in identNodes: # Single node name (without args, props or children)
    return newCall("initKNode", body.strIdent)

  var i = 1 # Index to start parsing args and props from (1 by default because )

  if body.kind == nnkCall: # A single node name with type annotation
    result = newCall("initKNode", body[0].strIdent, newTree(nnkExprEqExpr, ident"tag", newCall("some", body[1].strIdent)))    
    inc i
  else:
    body.expectKind(nnkCommand)
    body.expectMinLen(1)

    var tag = newCall("some", ident"string")
    var nodeName = body[0]

    if nodeName.kind == nnkCall: # Type annotation
      nodeName.expectLen(2)
      tag = newCall("some", nodeName[1].strIdent)
      nodeName = nodeName[0]
    
    result = newCall("initKNode", nodeName.strIdent, newTree(nnkExprEqExpr, ident"tag", tag))

    let args = newNimNode(nnkBracket)
    let props = newNimNode(nnkTableConstr)

    while i < body.len and body[i].kind != nnkStmtList:
      if body[i].kind == nnkExprEqExpr:
        props.add newTree(nnkExprColonExpr, body[i][0].strIdent, toKdlVal(body[i][1]))
      else:
        args.add newCall("initKVal", toKdlVal(body[i]))

      inc i

    result.add newTree(nnkExprEqExpr, ident"args", args)

    if props.len > 0:
      result.add newTree(nnkExprEqExpr, ident"props", newDotExpr(props, ident"toTable"))

  if i < body.len:
    body[i].expectKind(nnkStmtList)
    result.add newTree(nnkExprEqExpr, ident"children", newCall("toKdl", body[i]))

macro toKdlNode*(body: untyped): untyped = 
  ## Generate a KdlNode from Nim's AST
  runnableExamples:
    let node = toKdlNode:
      numbers (u8)10 (i32)20 myfloat=(f32)1.5:
        strings (uuid)"123e4567-e89b-12d3-a456-426614174000" (date)"2021-02-03" filter=(regex)r"$\d+"
        (author)person name="Alex"


  toKdlNodeImpl(body)

macro toKdl*(body: untyped): untyped = 
  if body.kind == nnkStmtList:
    let doc = newNimNode(nnkBracket)

    for command in body:
      doc.add toKdlNodeImpl(command)

    result = prefix(doc, "@")
  else:
    if body.kind == nnkNilLit:
      return newCall("initKNull")

    result = newCall("initKVal", body)
