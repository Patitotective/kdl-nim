## ## Encoder
## 

{.used.}

import nodes, utils, types

proc encode*[T: Value](obj: T, x: var KdlVal) = 
  x = obj.initKVal

proc encode*[T: Value](obj: T, x: var KdlNode, name: string) = 
  runnableExamples:
    import kdl
    assert 10.encode("node") == parseKdl("node 10")[0]

  x = initKNode(name)
  x.args.setLen(1)
  obj.encode(x[0])

proc encode*[T: Value](obj: openarray[T], x: var KdlNode, name: string) = 
  runnableExamples:
    import kdl
    assert @[10, 20].encode("node") == parseKdl("node 10 20")[0]

  x = initKNode(name)
  x.args.setLen(obj.len)
  for e, i in obj:
    i.encode(x[e])

proc encode*[T: Object](obj: openarray[T], x: var KdlNode, name: string) = 
  runnableExamples:
    import kdl
    assert @[(a: "Santiago", b: "Posteguillo"), (a: "Alva", b: "Majo")].encode("node") == parseKdl("node {- {a \"Santiago\"; b \"Posteguillo\"}; - {a \"Alva\"; b \"Majo\"}}")[0] 

  x = initKNode(name)
  x.children.setLen(obj.len)
  for e, i in obj:
    i.encode(x.children[e], "-")

proc encode*[T: Object](obj: T, x: var KdlDoc) = 
  runnableExamples:
    import kdl
    assert (name: "Pureya", version: "1.2.2").encode() == parseKdl("name \"Pureya\"; version \"1.2.2\"")

  when T is ref:
    if obj.isNil: return

  for field, val in (when T is ref: obj[].fieldPairs else: obj.fieldPairs):
    x.add val.encode(field)

proc encode*[T: Object](obj: T, x: var KdlNode, name: string) = 
  runnableExamples:
    import kdl
    assert (name: "Pureya", version: "1.2.2").encode("game") == parseKdl("game {name \"Pureya\"; version \"1.2.2\"}")

  x = initKNode(name)
  obj.encode(x.children)

proc encode*[T](obj: T, name: string): KdlNode = 
  obj.encode(result, name)

proc encode*[T](obj: T): KdlDoc = 
  obj.encode(result)
