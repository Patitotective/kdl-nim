import std/[algorithm, strformat, strutils, sequtils, tables]
import kdl/[parser, lexer, nodes]

export parser, nodes
export scanKdl, scanKdlFile, lexer.`$` # lexer

proc `$`*(val: KdlVal): string = 
  if val.annot.len > 0:
    result = &"({val.annot.escape})"

  result.add:
    case val.kind
    of KdlNumber:
      $val.getNumber()
    of KdlString:
      val.getString().escape
    of KdlBool:
      $val.getBool()
    of KdlNull:
      "null"
    of KdlEmpty:
      "empty"

proc `$`*(doc: KdlDoc): string

proc `$`*(node: KdlNode): string = 
  if node.annot.len > 0:
    result = &"({node.annot.escape})"

  result.add node.name.escape()

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1..node.args.high:
        result.add " "

      result.add $val

  if node.props.len > 0:
    result.add " "
    var count = 0
    for key, val in node.props:
      if count in 1..<node.props.len:
        result.add " "

      result.add &"{key.escape}={val}"

      inc count

  if node.children.len > 0:
    result.add " {\n"
    result.add indent($node.children, 2)
    result.add "\n}"

proc `$`*(doc: KdlDoc): string = 
  for e, node in doc:
    result.add $node
    if e < doc.high:
      result.add "\n"

proc prettyIdent*(ident: string): string = 
  if validToken(ident, tokenIdent):
    ident
  else:
    ident.escape()

proc pretty*(val: KdlVal): string = 
  if val.annot.len > 0:
    result = &"({val.annot.prettyIdent})"

  result.add:
    case val.kind
    of KdlNumber:
      if val.getNumber() == float int val.getNumber():
        $int(val.getNumber())
      else:
        $val.getNumber().formatFloat(ffScientific, -1)
    of KdlString:
      val.getString().escape()
    of KdlBool:
      $val.getBool()
    of KdlNull:
      "null"
    of KdlEmpty:
      "empty"

proc pretty*(node: KdlNode): string = 
  if node.annot.len > 0:
    result = &"({node.annot.prettyIdent})"

  result.add node.name.prettyIdent()

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1..node.args.high:
        result.add " "

      result.add val.pretty()

  if node.props.len > 0:
    result.add " "
    for e, (key, val) in node.props.pairs.toSeq.sortedByIt(it[0]):
      if e in 1..<node.props.len:
        result.add " "

      result.add &"{key.prettyIdent}={val.pretty}"

  if node.children.len > 0:
    result.add " {\n"
    result.add indent($node.children, 2)
    result.add "\n}"

proc pretty*(doc: KdlDoc): string = 
  ## Pretty print a KDL document according to the [translation rules](https://github.com/kdl-org/kdl/tree/main/tests#translation-rules)
  for e, node in doc:
    result.add node.pretty()
    if e < doc.len:
      result.add "\n"
