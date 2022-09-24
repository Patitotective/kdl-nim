## # kdl-nim
## kdl-nim is an implementation of the [KDL document language](https://kdl.dev) in the Nim programming language.
## ## Installation
## ```
## nimble install kdl
## ```
## ## Overview
## ### Parsing KDL
## kdl-nim parses strings (or files) into a `KdlDoc` which is a sequence of `KdlNode`s.
## 
## Each `KdlNode` holds a name, an optional type annotation (tag), zero ore more arguments, zero or more properties and optionally children nodes.
## 
## Arguments and properties' values are represented by an object variant `KdlVal`. `KdlVal` can be any of `KString`, `KFloat`, `KBool`, `KNull` or `KInt`.
runnableExamples:
  let doc = parseKdl("node 1 null {child \"abc\" true}") # You can also read files using parseKdlFile("file.kdl")

  assert doc[0][0].isInt() # 1
  assert doc[0][1].isNull() # null
  assert doc[0].children[0][0].isString() # "abc"
  assert doc[0].children[0][1].isBool() # true

## ### Reading nodes
runnableExamples:
  let doc = parseKdl("(tag)node 1 null key=\"val\" {child \"abc\" true}")

  assert doc[0].name == "node"
  assert doc[0].tag.isSome and doc[0].tag.get == "tag" # Tags are Option[string]
  assert doc[0]["key"] == "val" # Same as doc[0].props["key"]
  assert doc[0].children[0][0] == "abc" # Same as doc[0].children[0].args[0]

## ### Reading values
## Accessing to the inner value of any `KdlVal` can be achieved by using any of the following procedures:
## - `getString`
## - `getFloat`
## - `getBool`
## - `getInt`
runnableExamples:
  let doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  assert doc[0][0].getInt() == 1
  assert doc[0][1].getFloat() == 3.14
  assert doc[0].children[0][0].getString() == "abc"
  assert doc[0].children[0][1].getBool() == true

## There's also a generic procedure that converts `KdlValue` to the given type, consider this example:
runnableExamples:
  let doc = parseKdl("node 1 3.14 255")

  assert doc[0][0].get(float32) == 1f
  assert doc[0][1].get(int) == 3
  assert doc[0][2].get(uint8) == 255u8

## It only converts between numbers, you can't `val.get(string)` if `val.isBool()`.
## ### Setting values
runnableExamples:
  var doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  doc[0][0].setInt(10)
  assert doc[0][0] == 10

  doc[0].children[0][1].setBool(false)
  assert doc[0].children[0][1] == false

  # You can also use the generic procedure `setTo`
  doc[0][0].setTo(3.14)
  assert doc[0][0] == 3

  doc[0].children[0][0].setTo("def")
  assert doc[0].children[0][0] == "def"

## ### Creating KDL
## To create KDL documents, nodes or values without parsing you can also use the `toKdl`, `toKdlNode` and `toKdlVal` macros which have a similar syntax to KDL:
runnableExamples:
  let doc = toKdl:
    node[tag](1, true, nil, key="val"):
      child(3.14[pi])

    person(name="pat")

  assert doc == parseKdl("(tag)node 1 true null key=\"val\" {child (pi)3.14}; person name=\"pat\"")

  let node = toKdlNode: numbers(1, 2.13, 3.1e-10)
  assert node == parseKdl("numbers 1 2.13 3.1e-10")[0]

  assert toKdlVal("abc") == parseKdl("node \"abc\"")[0][0]

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
    of KFloat:
      $val.getFloat()
    of KString:
      val.getString().quoted
    of KBool:
      $val.getBool()
    of KNull:
      "null"
    of KInt:
      $val.getInt()
    of KEmpty:
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
    of KFloat:
      $val.getFloat()
    of KString:
      val.getString().quoted()
    of KBool:
      $val.getBool()
    of KNull:
      "null"
    of KInt:
      $val.getInt()
    of KEmpty:
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

proc writeFile*(doc: KdlDoc, path: string, pretty = false) = 
  ## Writes `doc` to path. Set `pretty` to true to use `pretty` instead of `$`.
  if pretty:
    writeFile(path, doc.pretty())
  else:
    writeFile(path, $doc & '\n')
