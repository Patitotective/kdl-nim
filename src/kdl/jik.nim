## # JiK
## This modules implements the JSON-in-KDL (JiK) specification to encode and decode JSON in KDL.
## 
## Checkout the official specification: https://github.com/kdl-org/kdl/blob/main/JSON-IN-KDL.md.
runnableExamples:
  import std/json
  import kdl

  const data = """
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
}}"""
  assert data.parseJson().toKdl() == parseKdl("""
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

  assert data.parseJson() == data.parseJson().toKdl().toJson()

import std/json
import nodes

proc toKVal(node: JsonNode): KdlVal = 
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

proc toKObject(node: JsonNode): KdlDoc = 
  assert node.kind == JObject

  for key, val in node:
    case val.kind
    of JObject:
      result.add initKNode(key, "object".some, children = val.toKObject)
    of JArray:
      result.add initKNode(key, "array".some, children = val.toKArray)
    else:
      result.add initKNode(key, args = [val.toKVal])

proc toKArray(node: JsonNode): KdlDoc = 
  assert node.kind == JArray

  for ele in node:
    case ele.kind
    of JObject:
      result.add initKNode("-", "object".some, children = ele.toKObject)
    of JArray:
      result.add initKNode("-", "array".some, children = ele.toKArray)
    else:
      result.add initKNode("-", args = [ele.toKVal])

proc toKdl*(node: JsonNode): KdlNode = 
  ## Converts node into its KDL representation.

  case node.kind
  of JObject:
    initKNode("-", "object".some, children = node.toKObject)
  of JArray:
    initKNode("-", "array".some, children = node.toKArray)
  else:
    initKNode("-", args = [node.toKVal])

proc toJson(val: KdlVal): JsonNode = 
  case val.kind
  of KString:
    result = newJString(val.getString)
  of KFloat:
    result = newJFloat(val.getFloat)
  of KBool:
    result = newJBool(val.getBool)
  of KNull:
    result = newJNull()
  of KInt:
    result = newJInt(val.getInt)
  else: discard

proc jsonKind(node: KdlNode): JsonNodeKind = 
  let tag = node.tag.get("")
  
  if tag  == "array":
    assert node.props.len == 0, "arrays cannot have properties in " & $node
    result = JArray
  elif tag == "object" or node.props.len > 0:
    assert node.len == 0, "objects cannot have arguments in " & $node
    result = JObject

  for child in node.children:
    if result == JArray:
      assert child.name == "-", "arrays' children have to be named \"-\" in " & $child
    elif child.name == "-" and result != JObject:
      result = JArray
    elif child.name != "-":
      result = JObject

    if result == JObject and child.jsonKind notin {JObject, JArray}:
      assert child.len in 0..1, "fields cannot have more than one argument in " & $child

proc toJson*(node: KdlNode): JsonNode

proc toJObject(node: KdlNode): JsonNode = 
  result = newJObject()
  
  for key, val in node.props:
    result[key] = val.toJson

  for child in node.children:
    result[child.name] = child.toJson

proc toJArray(node: KdlNode): JsonNode = 
  result = newJArray()

  for arg in node.args:
    result.add arg.toJson

  for child in node.children:
    result.add child.toJson

proc toJson*(node: KdlNode): JsonNode = 
  ## Converts node into its XML representation.

  case node.jsonKind
  of JArray:
    node.toJArray
  of JObject:
    node.toJObject
  else:
    assert node.len == 1, "unkown value in " & $node
    node[0].toJson
