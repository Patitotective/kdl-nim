import std/tables

type
  ValKind* = enum
    String, Number, Bool, Null

  Value* = object
    annotation*: string
    case kind*: ValKind
    of String:
      stringV*: string
    of Number:
      numV*: float64
    of Bool:
      boolV*: bool
    of Null:
      discard

  Node* = object
    annotation*: string
    name*: string
    args*: seq[Value]
    props*: Table[string, Value]

  Document* = object
    nodes*: seq[Node]
