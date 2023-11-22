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
import nodes, types

proc toKdl*(node: XmlNode, addComments = false): KdlNode =
  ## Converts node into its KDL representation.
  ## Ignores CDATA nodes, i.e..
  ## If `addComments` preserves XML comments as KDL nodes named `!`.

  case node.kind
  of xnText, xnVerbatimText:
    result = initKNode("-", args = toKdlArgs(node.text))
  of xnEntity:
    result = initKNode("-", args = toKdlArgs('&' & node.text & ';'))
  of xnComment:
    if addComments:
      result = initKNode("!", args = toKdlArgs(node.text))
  of xnElement:
    result = initKNode(node.tag)
    if not node.attrs.isNil:
      for key, val in node.attrs:
        result.props[key] = initKVal(val)

    if node.len == 1 and node[0].kind in {xnText, xnEntity, xnVerbatimText}:
      result.args.add initKVal(node[0].text)
    else:
      for child in node:
        if addComments or child.kind != xnComment:
          result.children.add child.toKdl(addComments)

  of xnCData: discard # According to XiK spec CDATA is discarded

proc toXmlSingle*(node: KdlNode): XmlNode =
  assert node.name.len == 1, "in " & $node
  assert node.args.len == 1, "single argument expected in " & $node

  case node.name[0]
  of '!':
    assert node.args.len == 1 and node.children.len == 0 and node.props.len == 0, "comments must have a single string argument in " & $node
    assert node.args[0].isString
    newComment(node.args[0].getString)
  of '-':
    let val = node.args[0].get(string)
    if val.len > 1 and val[0] == '&' and val[^1] == ';':
      newEntity(val[1..^2])
    else:
      newText(val)
  else:
    raise newException(ValueError, "Expected node named '!' or '-' in " & $node)

proc toXml*(node: KdlNode, addComments = false): XmlNode =
  ## Converts node into its XML representation.
  ## - If `addComments` preserves comments in elements, if node is a comment ('! "something"') it DOES return it.
  runnableExamples:
    import std/xmltree
    import kdl

    assert parseKdl("! \"comment\"")[0].toXml().kind == xnComment
    assert parseKdl("tag { ! \"comment\"; - \"text\" }")[0].toXml().len == 1 # Ignored the comment
    assert parseKdl("tag { ! \"comment\"; - \"text\" }")[0].toXml(addComments = true).len == 2 # Added the comment

  assert node.name.len > 0

  if node.name == "!" or node.name == "-":
    return toXmlSingle(node)

  assert node.args.len == 0 or (node.args.len == 1 xor node.children.len > 0), "single-argument and children cannot be mixed in " & $node
  result = newElement(node.name)

  result.attrs = newStringTable()
  for key, val in node.props:
    result.attrs[key] = val.get(string) # Stringify the values

  if node.args.len == 1:
    result.add newText(node.args[0].get(string))
  else:
    for child in node.children:
      assert child.name.len > 0
      if child.name == "!":
        if addComments:
          result.add toXmlSingle(child)
          continue
        else:
          continue

      if child.name == "-":
        result.add toXmlSingle(child)
      else:
        result.add child.toXml(addComments)

