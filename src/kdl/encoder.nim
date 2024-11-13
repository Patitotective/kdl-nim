## ## Encoder
## This module implements a serializer for different types and objects into KDL documents, nodes and values:
## - `char`
## - `bool`
## - `Option[T]`
## - `SomeNumber`
## - `StringTableRef`
## - `enum` and `HoleyEnum`
## - `string` and `cstring`
## - `KdlVal` (object variant)
## - `seq[T]` and `array[I, T]`
## - `set[Ordinal],` `HashSet[A]` and `OrderedSet[A]`
## - `Table[string, T]` and `OrderedTable[string, T]`
## - `object`, `ref` and `tuple` (including object variants)
## - Plus any type you implement.
##
## Use `encodeKdlDoc`, `encodeKdlNode` and `encodeKdlVal` correspondingly.
runnableExamples:
  import std/options
  import kdl

  type
    Package = object
      name*, version*: string
      authors*: Option[seq[string]]
      description*, licenseFile*, edition*: Option[string]

  const doc = parseKdl("""
name "kdl"
version "0.0.0"
authors {
- "Kat Marchán <kzm@zkat.tech>"
}
description "kats document language"
licenseFile "LICENSE.md"
edition "2018"
  """)

  const obj = Package(
    name: "kdl",
    version: "0.0.0",
    authors: @["Kat Marchán <kzm@zkat.tech>"].some,
    description: "kats document language".some,
    licenseFile: "LICENSE.md".some,
    edition: "2018".some
  )

  assert obj.encodeKdlDoc() == doc

## ### Custom Encode Hooks
## If you need to encode a specific type in a specific way you may create a custom encode hooks.
##
## To do so, you'll have to overload the `encodeKdl` procedure with the following signature:
## ```nim
## proc encodeKdl*(a: MyType, v: var KdlSome)
## ```
## Where `KdlSome` is one of `KdlDoc`, `KdlNode` or `KdlVal`.
## *Note: to understand it better think about it like encoding `a` into `v`, where `v` can be a KDL document, node or value.*
runnableExamples:
  import std/times
  import kdl

  proc encodeKdl*(a: DateTime, v: var KdlDoc) =
    v = @[
      initKNode("year", args = @[encodeKdlVal(a.year)]),
      initKNode("month", args = @[encodeKdlVal(a.month)]),
      initKNode("day", args = @[encodeKdlVal(a.monthday)]),
      initKNode("hour", args = @[encodeKdlVal(a.hour)]),
      initKNode("minute", args = @[encodeKdlVal(a.minute)]),
      initKNode("second", args = @[encodeKdlVal(a.second)]),
      initKNode("nanosecond", args = @[encodeKdlVal(a.nanosecond)]),
    ]

  const doc = parseKdl("""
"year" 2022
"month" "October"
"day" 15
"hour" 12
"minute" 4
"second" 0
"nanosecond" 0
  """)

  assert dateTime(2022, mOct, 15, 12, 04).encodeKdlDoc() == doc

import std/[typetraits, strformat, enumerate, options, strtabs, tables, sets]
import nodes, utils, types

# TODO: provide custom encoding for a specific field in a specific object

# ----- Index -----

proc encodeKdlDoc*(a: auto): KdlDoc
proc encodeKdlNode*(a: auto, name: string): KdlNode
proc encodeKdlVal*(a: auto): KdlVal
proc encodeKdl*(a: ref, v: var KdlSome)

proc encodeKdl*(a: KdlDoc, v: var KdlDoc)
proc encodeKdl*(a: List, v: var KdlDoc)
proc encodeKdl*(a: SomeTable[string, auto] or StringTableRef, v: var KdlDoc)
proc encodeKdl*(a: SomeSet[auto], v: var KdlDoc)
proc encodeKdl*[T: Ordinal](a: set[T], v: var KdlDoc)
proc encodeKdl*(a: Object, v: var KdlDoc)

proc encodeKdl*(a: KdlNode, v: var KdlNode, name: string)
proc encodeKdl*(a: KdlDoc, v: var KdlNode, name: string)
proc encodeKdl*(a: KdlVal, v: var KdlNode, name: string)
proc encodeKdl*(a: List, v: var KdlNode, name: string)
proc encodeKdl*[T: Ordinal](a: set[T], v: var KdlNode, name: string)
proc encodeKdl*(a: SomeTable[string, auto] or SomeSet[auto], v: var KdlNode, name: string)
proc encodeKdl*(a: StringTableRef, v: var KdlNode, name: string)
proc encodeKdl*(a: Option[auto], v: var KdlNode, name: string)
proc encodeKdl*(a: Object, v: var KdlNode, name: string)
proc encodeKdl*(a: auto, v: var KdlNode, name: string)

proc encodeKdl*(a: KdlVal, v: var KdlVal)
proc encodeKdl*(a: Value, v: var KdlVal)
proc encodeKdl*(a: cstring, v: var KdlVal)
proc encodeKdl*(a: char, v: var KdlVal)
proc encodeKdl*(a: enum, v: var KdlVal)
proc encodeKdl*(a: List, v: var KdlVal)
proc encodeKdl*(a: Option[auto], v: var KdlVal)
# proc encodeKdl*[T: KdlNode or KdlDoc](a: T, v: var KdlVal)

# ----- KdlSome -----

proc encodeKdlDoc*(a: auto): KdlDoc =
  mixin encodeKdl
  encodeKdl(a, result)

proc encodeKdlNode*(a: auto, name: string): KdlNode =
  mixin encodeKdl
  encodeKdl(a, result, name)

proc encodeKdlVal*(a: auto): KdlVal =
  mixin encodeKdl
  encodeKdl(a, result)

proc encodeKdl*(a: ref, v: var KdlSome) =
  ## Short for `encodeKdl(a[], v)`
  encodeKdl(a[], v)

# ----- KdlDoc -----

proc encodeKdl*(a: KdlDoc, v: var KdlDoc) =
  v = a

proc encodeKdl*(a: List, v: var KdlDoc) =
  v.setLen(a.len)
  for e, i in a:
    encodeKdl(i, v[e], "-")

proc encodeKdl*(a: SomeTable[string, auto] or StringTableRef, v: var KdlDoc) =
  when a is StringTableRef:
    if a.isNil:
      v.setLen(0)
      return

  v.setLen(a.len)
  for e, (key, val) in enumerate(a.pairs):
    encodeKdl(val, v[e], key)

proc encodeKdl*(a: SomeSet[auto], v: var KdlDoc) =
  v.setLen(a.len)
  for e, i in enumerate(a):
    encodeKdl(i, v[e], "-")

proc encodeKdl*[T: Ordinal](a: set[T], v: var KdlDoc) =
  v.setLen(a.len)
  for e, i in a:
    encodeKdl(i, v[e], "-")

proc encodeKdl*(a: Object, v: var KdlDoc) =
  v.setLen(0)
  type T = typeof(a)
  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    for _, field in a.fieldPairs:
      v.add encodeKdlNode(field, "-")
  else:
    for fieldName, field in a.fieldPairs:
      v.add encodeKdlNode(field, fieldName)

# ----- KdlNode -----

proc encodeKdl*(a: KdlNode, v: var KdlNode, name: string) =
  v = a
  v.name = name

proc encodeKdl*(a: KdlDoc, v: var KdlNode, name: string) =
  v = initKNode(name, children = a)

proc encodeKdl*(a: KdlVal, v: var KdlNode, name: string) =
  v = initKNode(name, args = @[a])

proc encodeKdl*(a: List, v: var KdlNode, name: string) =
  v = initKNode(name)
  v.children.setLen(a.len)
  for e, i in a:
    encodeKdl(i, v.children[e], "-")

proc encodeKdl*[T: Ordinal](a: set[T], v: var KdlNode, name: string) =
  v = initKNode(name)
  v.args.setLen(a.len)
  for e, i in enumerate(a):
    v.args[e] = encodeKdlVal(i)

proc encodeKdl*(a: SomeTable[string, auto] or SomeSet[auto], v: var KdlNode,
    name: string) =
  v = initKNode(name)
  encodeKdl(a, v.children)

proc encodeKdl*(a: StringTableRef, v: var KdlNode, name: string) =
  v = initKNode(name)
  if a.isNil: return

  for key, val in a:
    v.props[key] = encodeKdlVal(val)

proc encodeKdl*(a: Option[auto], v: var KdlNode, name: string) =
  if a.isNone:
    v = initKNode(name)
  else:
    encodeKdl(a.get, v, name)

proc encodeKdl*(a: Object, v: var KdlNode, name: string) =
  ## Encode `a` fields as `v` children
  v = initKNode(name)
  encodeKdl(a, v.children)

proc encodeKdl*(a: auto, v: var KdlNode, name: string) =
  ## Encodes a as the first argument of v, thus as a KdlVal
  v = initKNode(name, args = @[encodeKdlVal(a)])

# ----- KdlVal -----

proc encodeKdl*(a: KdlVal, v: var KdlVal) =
  v = a

proc encodeKdl*(a: Value, v: var KdlVal) =
  ## Encodes it using initKVal
  v = initKVal(a)

proc encodeKdl*(a: cstring, v: var KdlVal) =
  ## Encodes a as null if a is nil, otherwise encodes it as a string
  if a.isNil:
    v = initKNull()
  else:
    v = initKString($a)

proc encodeKdl*(a: char, v: var KdlVal) =
  ## Encodes a as a string
  v = initKString($a)

proc encodeKdl*(a: enum, v: var KdlVal) =
  ## Encodes a as a string
  v = initKString($a)

proc encodeKdl*(a: List, v: var KdlVal) =
  ## Encodes the first element of a if a only has one element.
  check a.len == 1, &"cannot encode {$typeof(a)} to {$typeof(v)} in {a}"
  encodeKdl(a[0], v)

proc encodeKdl*(a: Option[auto], v: var KdlVal) =
  ## Encodes a as null if a is none, otherwise encodes a.get
  if a.isNone:
    v = initKNull()
  else:
    encodeKdl(a.get, v)

# proc encodeKdl*[T: KdlNode or KdlDoc](a: T, v: var KdlVal) =
#   fail &"{$typeof(a)} not implemented for {$typeof(v)} in {a}"

