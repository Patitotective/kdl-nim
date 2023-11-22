## # JiK
## This modules implements the JSON-in-KDL (JiK) specification to encode and decode JSON in KDL.
##
## Checkout the official specification: https://github.com/kdl-org/kdl/blob/main/JSON-IN-KDL.md.
runnableExamples:
  import std/json
  import kdl

  let data = """
{"widget": {
    "debug": "on",
    "window": {
        "title": "Sample Konfabulator Widget",
        "name": "main_window",
        "width": 500,
        "height": 500
    },
    "image": {
        "src": "Images/Sun.png",
        "name": "sun1",
        "hOffset": 250,
        "vOffset": 250,
        "alignment": "center"
    },
    "text": {
        "data": "Click Here",
        "size": 36,
        "style": "bold",
        "name": "text1",
        "hOffset": 250,
        "vOffset": 100,
        "alignment": "center",
        "onMouseUp": "sun1.opacity = (sun1.opacity / 100) * 90;"
    }
}}""".parseJson()
  assert data.toKdl() == parseKdl("""
(object)- {
    (object)widget {
        debug "on"
        (object)window {
            title "Sample Konfabulator Widget"
            name "main_window"
            width 500
            height 500
        }
        (object)image {
            src "Images/Sun.png"
            name "sun1"
            hOffset 250
            vOffset 250
            alignment "center"
        }
        (object)text {
            data "Click Here"
            size 36
            style "bold"
            name "text1"
            hOffset 250
            vOffset 100
            alignment "center"
            onMouseUp "sun1.opacity = (sun1.opacity / 100) * 90;"
        }
    }
}""")[0]

  assert data == data.toKdl().toJson()

{.used.}

import std/[json, sets]
import nodes, types


proc toKVal(node: JsonNode): KdlVal =
  assert node.kind in {JString, JInt, JFloat, JBool, JNull}

  case node.kind
  of JString:
    result = initKVal(node.getStr)
  of JInt:
    result = initKVal(node.getInt)
  of JFloat:
    result = initKVal(node.getFloat)
  of JBool:
    result = initKVal(node.getBool)
  of JNull:
    result = initKNull()
  else: discard

proc toKArray(node: JsonNode): KdlDoc
proc toKdl*(node: JsonNode, name = "-"): KdlNode

proc toKObject(node: JsonNode): KdlDoc =
  assert node.kind == JObject

  for key, val in node:
    result.add val.toKdl(key)

proc toKArray(node: JsonNode): KdlDoc =
  assert node.kind == JArray

  for ele in node:
    result.add ele.toKdl()

proc toKdl*(node: JsonNode, name = "-"): KdlNode =
  ## Converts node into a KDL node.
  case node.kind
  of JObject:
    initKNode(name, "object".some, children = node.toKObject)
  of JArray:
    initKNode(name, "array".some, children = node.toKArray)
  else:
    initKNode(name, args = [node.toKVal])

proc toJVal(val: KdlVal): JsonNode =
  case val.kind
  of KString:
    newJString(val.getString)
  of KFloat:
     newJFloat(val.getFloat)
  of KBool:
    newJBool(val.getBool)
  of KNull:
    newJNull()
  of KInt:
    newJInt(val.getInt)
  of KEmpty:
    nil

proc toJson*(node: KdlNode): JsonNode

proc toJObject(node: KdlNode): JsonNode =
  result = newJObject()

  for key, val in node.props:
    result[key] = val.toJVal()

  for child in node.children:
    result[child.name] = child.toJson()

proc toJArray(node: KdlNode): JsonNode =
  result = newJArray()

  for arg in node.args:
    result.add arg.toJVal()

  for child in node.children:
    result.add child.toJson()

proc toJson*(node: KdlNode): JsonNode =
  ## Converts node into its JSON representation.
  let tag = node.tag.get("")
  if tag == "array":
    node.toJArray()
  elif tag == "object":
    node.toJObject()
  elif node.args.len == 1 and node.props.len == 0 and node.children.len == 0:
    node.args[0].toJVal()
  elif node.props.len == 0 and (node.args.len > 0 or node.children.len > 0):
    for child in node.children:
      if child.name != "-":
        raise newException(ValueError, "All node's children must be named - for a JiK Array")

    node.toJArray()
  elif node.args.len == 0 and (node.props.len > 0 or node.children.len > 0):
    var names = initHashSet[string]()
    for key, _ in node.props:
      names.incl key

    for child in node.children:
      if child.name in names:
        raise newException(ValueError, "All node's children must have different names for a JiK Object")

      names.incl child.name

    node.toJObject()
  else:
    raise newException(ValueError, "Invalid JiK node")

