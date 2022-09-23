import std/[algorithm, strformat, strutils, sequtils, options, tables]
import kdl/[parser, lexer, nodes, utils]

export parser, nodes
export utils except quoted
export scanKdl, scanKdlFile, lexer.`$` # lexer

proc `$`*(val: KdlVal): string = 
  if val.tag.isSome:
    result = &"({val.tag.get.quoted})"

  result.add:
    case val.kind
    of KdlFloat:
      $val.getFloat()
    of KdlString:
      val.getString().quoted
    of KdlBool:
      $val.getBool()
    of KdlNull:
      "null"
    of KdlInt:
      $val.getInt()
    of KdlEmpty:
      "empty"

proc `$`*(doc: KdlDoc): string

proc `$`*(node: KdlNode): string = 
  if node.tag.isSome:
    result = &"({node.tag.get.quoted})"

  result.add node.name.quoted()

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

      result.add &"{key.quoted}={val}"

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
    ident.quoted()

proc pretty*(val: KdlVal): string = 
  if val.tag.isSome:
    result = &"({val.tag.get.prettyIdent})"

  result.add:
    case val.kind
    of KdlFloat:
      $val.getFloat().formatFloat(ffScientific, 1)
    of KdlString:
      val.getString().quoted()
    of KdlBool:
      $val.getBool()
    of KdlNull:
      "null"
    of KdlInt:
      $val.getInt()
    of KdlEmpty:
      "empty"

proc pretty*(doc: KdlDoc, newLine = true): string 

proc pretty*(node: KdlNode): string = 
  if node.tag.isSome:
    result = &"({node.tag.get.prettyIdent})"

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
    result.add indent(node.children.pretty(newLine = false), 4)
    result.add "\n}"

proc pretty*(doc: KdlDoc, newLine = true): string = 
  ## Pretty print a KDL document according to the [translation rules](https://github.com/kdl-org/kdl/tree/main/tests#translation-rules).
  ## 
  ## If `newLine`, inserts a new line at the end.
  for e, node in doc:
    result.add node.pretty()
    if e < doc.high:
      result.add "\n"

  if newLine: result.add "\n"
