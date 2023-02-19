import std/[options, tables]

type
  KdlError* = object of CatchableError
  KdlLexerError* = object of KdlError
  KdlParserError* = object of KdlError

  KValKind* = enum
    KEmpty, 
    KString, 
    KFloat, 
    KBool, 
    KNull
    KInt, 

  KdlVal* = object
    tag*: Option[string] # Type annotation

    case kind*: KValKind
    of KString:
      str*: string
    of KFloat:
      fnum*: float
    of KBool:
      boolean*: bool
    of KNull, KEmpty:
      discard
    of KInt:
      num*: int64

  KdlProp* = tuple[key: string, val: KdlVal]

  KdlNode* = object
    tag*: Option[string]
    name*: string
    args*: seq[KdlVal]
    props*: Table[string, KdlVal]
    children*: seq[KdlNode]

  KdlDoc* = seq[KdlNode]

  KdlPrefs*[T] = object
    path*: string
    default*: T
    content*: T
