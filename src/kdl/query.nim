import types

type
  Query* = seq[Selector]

  Selector* = seq[NodeFilter]

  Operator* = enum
    opEqual # =
    opNoEqual # !=
    opDescend # >>
    opGreater # >
    opLess # <
    opGreaterEq # >=
    opLessEq # <=
    opStarts # ^
    opEnds # $
    opContains # *

  NodeFilter* = object
    matchers*: seq[Matcher]
    operator*: Operator

  Matcher* = object
    accessor*: Accessor
    operator*: Operator
    value*: KdlVal # Comparision value

  AccessorKind* = enum
    Name
    Prop
    Val
    Props
    Values

  Accessor* = object
    case kind*: AccessorKind
    of Prop:
      prop*: string
    of Val:
      index*: Natural
    else: discard

  Mapping*[T: Accessor or seq[Accessor]] = T

