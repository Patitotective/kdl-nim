## # XiK
## This modules implements the XML-in-KDL (XiK) specification to encode and decode XML in KDL.
## 
## Checkout the official specification: https://github.com/kdl-org/kdl/blob/main/XML-IN-KDL.md.
runnableExamples:
  import std/[xmlparser, xmltree]
  import kdl

  const data = """
<breakfast_menu>
<food>
<name>Belgian Waffles</name>
<price>$5.95</price>
<description>
Two of our famous Belgian Waffles with plenty of real maple syrup
</description>
<calories>650</calories>
</food>
<food>
<name>Strawberry Belgian Waffles</name>
<price>$7.95</price>
<description>
Light Belgian waffles covered with strawberries and whipped cream
</description>
<calories>900</calories>
</food>
</breakfast_menu>"""
  assert data.parseXml().toKdl() == parseKdl("""
breakfast_menu {
  food {
    name "Belgian Waffles"
    price "$5.95"
    description "Two of our famous Belgian Waffles with plenty of real maple syrup\n"
    calories "650"
  }
  food {
    name "Strawberry Belgian Waffles"
    price "$7.95"
    description "Light Belgian waffles covered with strawberries and whipped cream\n"
    calories "900"
  }
}""")[0]

  assert $data.parseXml() == $data.parseXml().toKdl().toXml()

{.used.}

import std/[strtabs, xmltree]
import nodes

proc toKdl*(node: XmlNode, comments = false): KdlNode = 
  ## Converts node into its KDL representation.
  ## - If `comments` preserves comments.

  case node.kind
  of xnText, xnEntity, xnVerbatimText:
    result = toKdlNode: "-"(node.text)
  of xnComment:
    if comments:
      result = toKdlNode: "!"(node.text)
  of xnElement:
    result = initKNode(node.tag)
    if node.attrsLen > 0:
      for key, val in node.attrs:
        result.props[key] = initKVal(val)

    if node.len == 1 and node[0].kind in {xnText, xnEntity, xnVerbatimText}:
      result.args.add initKVal(node[0].text)
    else:
      for child in node:
        if comments or child.kind != xnComment:
          result.children.add child.toKdl(comments)

  of xnCData: discard # According to XiK spec CDATA is discarded

proc toXml*(node: KdlNode, comments = false): XmlNode = 
  ## Converts node into its XML representation.
  ## - If `comments` preserves comments.

  result = newElement(node.name)

  assert (node.args.len > 0 and node.children.len == 0) or (node.args.len == 0 and node.children.len > 0) or (node.args.len == 0 and node.children.len == 0), "nodes have to have either one argument and zero children, zero arguments and zero or more children"

  if node.props.len > 0:
    result.attrs = newStringTable()
    for key, val in node.props:
      assert val.isString, "properties' values have to be of type string"
      result.attrs[key] = val.getString

  if node.args.len > 0:
    assert node.args.len == 1 and node.args[0].isString, "first argument has to be a string and there must be only one argument"
    result.add newText(node.args[0].getString)
  else:
    for child in node.children:
      case child.name
      of "-":
        assert child.args.len == 1 and child.args[0].isString, "first argument has to be a string and there must be only one argument"
        result.add newText(child.args[0].getString)
      of "!":
        assert child.args.len == 1 and child.args[0].isString, "first argument has to be a string and there must be only one argument"
        if comments:
          result.add newComment(child.args[0].getString)
      else:
        result.add child.toXml(comments)
