import std/[strformat, strutils]

type
  KdlValKind* = enum
    KdlEmpty, 
    KdlNumber, 
    KdlString, 
    KdlBool, 
    KdlNull

  KdlVal* = object
    annot*: string # Type annotation

    case kind*: KdlValKind
    of KdlNumber:
      num*: float
    of KdlString:
      str*: string
    of KdlBool:
      boolean*: bool
    of KdlEmpty, KdlNull:
      discard

  KdlProp* = object
    key*: string
    val*: KdlVal

  KdlNode* = object
    annot*: string
    name*: string
    args*: seq[KdlVal]
    props*: seq[KdlProp]
    children*: seq[KdlNode]

  KdlDoc* = seq[KdlNode]

proc initKVal*(val: float, annot = ""): KdlVal = 
  KdlVal(annot: annot, kind: KdlNumber, num: val)

proc initKVal*(val: string, annot = ""): KdlVal = 
  KdlVal(annot: annot, kind: KdlString, str: val)

proc initKVal*(val: bool, annot = ""): KdlVal = 
  KdlVal(annot: annot, kind: KdlBool, boolean: val)

proc initKNumber*(val: float = default float, annot = ""): KdlVal = 
  initKVal(val, annot)

proc initKString*(val: string = default string, annot = ""): KdlVal = 
  initKVal(val, annot)

proc initKBool*(val: bool = default bool, annot = ""): KdlVal = 
  initKVal(val, annot)

proc initKNull*(annot = ""): KdlVal = 
  KdlVal(annot: annot, kind: KdlNUll)

proc getNumber*(val: KdlVal): float = 
  assert val.kind == KdlNumber
  val.num

proc getString*(val: KdlVal): string = 
  assert val.kind == KdlString
  val.str

proc getBool*(val: KdlVal): bool = 
  assert val.kind == KdlBool
  val.boolean

proc isNull*(val: KdlVal): bool = 
  val.kind == KdlNull

proc isEmpty*(val: KdlVal): bool = 
  val.kind == KdlEmpty

proc `$`*(val: KdlVal): string = 
  if val.annot.len > 0:
    result = &"({val.annot})"

  case val.kind
  of KdlNumber:
    result.add $val.getNumber()
  of KdlString:
    result.addQuoted val.getString()
  of KdlBool:
    result.add $val.getBool()
  of KdlNull:
    result.add "null"
  of KdlEmpty:
    result.add "empty"

proc initKNode*(name: string, annot = "", args = newSeq[KdlVal](), props = newSeq[KdlProp](), children = newSeq[KdlNode]()): KdlNode = 
  KdlNode(annot: annot, name: name, args: args, props: props, children: children)

proc initKProp*(key: string, val: KdlVal): KdlProp = 
  KdlProp(key: key, val: val)

proc pretty*(node: KdlNode): string = 
  if node.annot.len > 0:
    result = &"({node.annot})"

  result.add node.name

  if node.args.len > 0:
    result.add node.args.join(" ")

  if node.props.len > 0:
    result.add node.props.join(" ")
