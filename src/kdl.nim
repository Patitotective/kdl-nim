import std/[algorithm, strformat, strutils, sequtils, tables]
import kdl/[parser, lexer, nodes]

export parser, nodes
export scanKdl, scanKdlFile # lexer

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

# proc `$`*(node: KdlNode): string = 


proc prettyIdent*(ident: string): string = 
  if validToken(ident, tokenIdent):
    result = ident
  else:
    result.addQuoted(ident)

proc pretty*(val: KdlVal): string = 
  if val.annot.len > 0:
    result = &"({val.annot.prettyIdent})"

  case val.kind
  of KdlNumber:
    if val.getNumber() == float int val.getNumber():
      result.add $int(val.getNumber())
    else:
      result.add val.getNumber().formatFloat(ffScientific, -1)
  of KdlString:
    result.addQuoted val.getString()
  of KdlBool:
    result.add $val.getBool()
  of KdlNull:
    result.add "null"
  of KdlEmpty:
    result.add "empty"

proc pretty*(node: KdlNode): string = 
  if node.annot.len > 0:
    result = &"({node.annot.prettyIdent})"

  result.add node.name.prettyIdent()

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e > 0 and e < node.args.len:
        result.add " "

      result.add val.pretty()

  if node.props.len > 0:
    result.add " "
    for e, (key, val) in node.props.pairs.toSeq.sortedByIt(it[0]):
      if e > 0 and e < node.props.len:
        result.add " "

      result.add &"{key.prettyIdent}={val.pretty}"

proc pretty*(doc: KdlDoc): string = 
  ## Pretty print a KDL document according to the [translation rules](https://github.com/kdl-org/kdl/tree/main/tests#translation-rules)
  for e, node in doc:
    result.add node.pretty()
    if e >= 0:
      result.add "\n"
