# kdl-nim
[![Nim](https://img.shields.io/badge/Made%20with%3A-Nim-yellow?style=flat&logo=nim&logoColor=white)](https://nim-lang.org)
[![Tests](https://github.com/Patitotective/kdl-nim/actions/workflows/tests.yml/badge.svg)](https://github.com/Patitotective/kdl-nim/actions/workflows/tests.yml)

KDL Nim implementation.

## Installation
```
nimble install kdl
```
Or directly from this repository:
```
nimble install https://github.com/Patitotective/kdl-nim
```

## Overview
```nim
import kdl

var doc = parseKdl("""
// Nodes can be separated into multiple lines
title \
  "Some title"


// Files must be utf8 encoded!
smile (emoji)"😁" {
  upside-down (emoji)"🙃"
}

// Instead of anonymous nodes, nodes and properties can be wrapped
// in "" for arbitrary node names.
"!@#$@$%Q#$%~@!40" "1.2.3" "!!!!!"=true

// The following is a legal bare identifier:
foo123~!@#$%^&*.:'|?+ "weeee"

// And you can also use unicode!
ノード　お名前="☜(ﾟヮﾟ☜)"

// kdl specifically allows properties and values to be
// interspersed with each other, much like CLI commands.
foo bar=true "baz" quux=false 1 2 3
""") # You can also read files using parseKdlFile("file.kdl")

assert doc[0][0].isString() # title "Some title"

assert doc[1][0] == "😁" # smile node
assert doc[1][0].tag.isSome and doc[1][0].tag.get == "emoji" # Type annotation
assert doc[1].children[0][0] == "🙃" # smile node's upside-down child

assert doc[2].name == "!@#$@$%Q#$%~@!40"

assert doc[^1]["quux"] == false

doc[0][0].setString("New title")

# toKdlNode is a macro that facilitates the creation of `KdlNode`s, there's also toKdl (to create documents) and toKdlVal
doc[1].children[0] = toKdlNode: sunglasses("😎"[emoji], 3.14)

assert $doc[1].children[0] == "\"sunglasses\" (\"emoji\")\"😎\" 3.14"

assert doc[1].children[0][1].get(uint8) == 3u8 # Converts 3.14 into an uint8

doc[^1]["bar"].setTo(false) # Same as setBool(false)

doc.writeFile("doc.kdl")
```

## Docs
Documentation is live at https://patitotective.github.io/kdl-nim/.

## TODO
- Make the lexer and parser work with `openArray[char]` or `cstring`
- Implement [KDL schema language](https://github.com/kdl-org/kdl/blob/main/SCHEMA-SPEC.md).
- Implement [KDL query language](https://github.com/kdl-org/kdl/blob/main/QUERY-SPEC.md).

## About
- GitHub: https://github.com/Patitotective/kdl-nim.
- Discord: https://discord.gg/as85Q4GnR6.
- Docs: https://patitotective.github.io/kdl-nim/.

Contact me:
- Discord: **Patitotective#0127**.
- Twitter: [@patitotective](https://twitter.com/patitotective).
- Email: **cristobalriaga@gmail.com**.
