## # kdl-nim
## kdl-nim is an implementation of the [KDL document language](https://kdl.dev) v1.0.0 in the Nim programming language.
##
## ## Installation
## ```
## nimble install kdl
## ```
##
## ## Overview
## ### Parsing KDL
## kdl-nim parses strings, files or streams into a `KdlDoc` which is a sequence of `KdlNode`s.
##
## Each `KdlNode` holds a name, an optional type annotation (tag), zero ore more arguments, zero or more properties and optionally children nodes.
## Arguments are a sequence of values, while properties are an unordered table of string and values.
## Arguments and properties' values are represented by the object variant `KdlVal`. `KdlVal` can be of any kind `KString`, `KFloat`, `KBool`, `KNull` or `KInt`.
runnableExamples:
  let doc = parseKdl("node (i8)1 null key=\"val\" {child \"abc\" true}") # You can also read files using parseKdlFile("file.kdl")
  assert doc == @[
    initKNode("node",
      args = @[initKVal(1, "i8".some), initKNull()],
      props = {"key": initKVal("val")}.toTable,
      children = @[initKNode("child", args = @[initKVal("abc"), initKVal(true)])])
    ]

## ### Reading nodes
runnableExamples:
  let doc = parseKdl("(tag)node 1 null key=\"val\" {child \"abc\" true}")

  assert doc[0].name == "node"
  assert doc[0].tag.isSome and doc[0].tag.get == "tag" # Tags are Option[string]
  assert doc[0]["key"] == "val" # Same as doc[0].props["key"]
  assert doc[0].children[0].args[0] == "abc" # Same as doc[0].children[0].args[0]

## ### Reading values
## Accessing to the inner value of any `KdlVal` can be achieved by using any of the following procedures:
## - `getString`
## - `getFloat`
## - `getBool`
## - `getInt`
runnableExamples:
  let doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  assert doc[0].args[0].getInt() == 1
  assert doc[0].args[1].getFloat() == 3.14
  assert doc[0].children[0].args[0].getString() == "abc"
  assert doc[0].children[0].args[1].getBool() == true

## There's also a generic procedure that converts `KdlValue` to the given type, consider this example:
runnableExamples:
  let doc = parseKdl("node 1 3.14 255")

  assert doc[0].args[0].get(float32) == 1f
  assert doc[0].args[1].get(int) == 3
  assert doc[0].args[2].get(uint8) == 255u8
  assert doc[0].args[0].get(string) == "1"

## ### Setting values
runnableExamples:
  var doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  doc[0].args[0].setInt(10)
  assert doc[0].args[0] == 10

  doc[0].children[0].args[1].setBool(false)
  assert doc[0].children[0].args[1] == false

  # You can also use the generic procedure `setTo`
  doc[0].args[0].setTo(3.14)
  assert doc[0].args[0] == 3

  doc[0].children[0].args[0].setTo("def")
  assert doc[0].children[0].args[0] == "def"

## ### Creating KDL
## To create KDL documents, nodes or values without parsing or object constructors you can use the `toKdlDoc`, `toKdlNode` and`toKdlVal` macros which have a similar syntax to KDL:
runnableExamples:
  let doc = toKdlDoc:
    node[tag](1, true, nil, key="val"):
      child(3.14[pi])

    person(name="pat")

  assert doc == parseKdl("(tag)node 1 true null key=\"val\" {child (pi)3.14}; person name=\"pat\"")

  let node = toKdlNode: numbers(1, 2.13, 3.1e-10)
  assert node == parseKdl("numbers 1 2.13 3.1e-10")[0]

  assert toKdlVal("abc"[tag]) == parseKdl("node (tag)\"abc\"")[0].args[0]

## Furthermore there are the `toKdlArgs` and `toKdlProps` macros, they provide shortcuts for creating a sequence and a table of `KdlVal`:
runnableExamples:
  assert toKdlArgs(1, 2[tag], "a") == [1.initKVal, 2.initKVal("tag".some), "a".initKVal]
  assert toKdlProps({"a": 1[tag], "b": 2}) == {"a": 1.initKVal("tag".some), "b": 2.initKVal}.toTable

## ## Compile flags
## `-d:kdlDecoderAllowHoleyEnums`: to allow converting integers into holey enums.
## `-d:kdlDecoderNoCaseTransitionError`: to not get a compile error when trying to change a discriminator field from an object variant in an init hook.

## ## More
## Checkout these other useful modules:
## - [kdl/encoder](kdl/encoder.html) for KDL serializing (Nim objects to KDL)
## - [kdl/decoder](kdl/decoder.html) for KDL deserializing (KDL to Nim objects)
## - [kdl/xix](kdl/xik.html) for [XML-in-KDL](https://github.com/kdl-org/kdl/blob/main/XML-IN-KDL.md)
## - [kdl/jix](kdl/jix.html) for [JSON-in-KDL](https://github.com/kdl-org/kdl/blob/main/JSON-IN-KDL.md)
## - [kdl/prefs](kdl/prefs.html) for a simple preferences sytem.

import std/[algorithm, enumerate, strformat, strutils, sequtils, options, tables]

import kdl/[decoder, encoder, parser, lexer, nodes, types, utils, xik, jik]

export decoder, encoder, parser, nodes, types
export scanKdl, scanKdlFile, lexer.`$` # lexer

func indent(s: string, count: Natural, padding = " ", newLine = "\n"): string =
  for e, line in enumerate(s.splitLines):
    if e > 0:
      result.add newLine

    for j in 1..count:
      result.add padding

    result.add line

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
    result.add " {\p"
    result.add indent(node.children.pretty(newLine = false), 4, newLine = "\p")
    result.add "\p}"

proc pretty*(doc: KdlDoc, newLine = true): string =
  ## Pretty print a KDL document according to the [translation rules](https://github.com/kdl-org/kdl/tree/main/tests#translation-rules).
  ##
  ## If `newLine`, inserts a new line at the end.
  for e, node in doc:
    result.add node.pretty()
    if e < doc.high:
      result.add "\p"

  if newLine: result.add "\p"

proc writeFile*(path: string, doc: KdlDoc, pretty = false) =
  ## Writes `doc` to path. Set `pretty` to true to use `pretty` instead of `$`.
  if pretty:
    writeFile(path, doc.pretty())
  else:
    writeFile(path, $doc & '\n')

