import std/[strformat, strutils]

import npeg

type
  NumKind* = enum
    nkDec, nkHex, nkBin, nkOct

  TokenKind* = enum
    tkNull, 
    tkBool, 
    tkEqual, 
    tkIdent, 
    tkNumber, 
    tkString, 
    tkTypeAnnot, 
    tkOpenBlock, tkCloseBlock, # Children block

  Coord = tuple[line, col: int]

  Token* = object
    coord*: Coord
    lexeme*: string
    case kind*: TokenKind
    of tkBool, tkNull, tkIdent, tkOpenBlock, tkCloseBlock, tkEqual: 
      discard
    of tkTypeAnnot:
      typeAnnot*: string
    of tkString:
      strVal*: string
      raw*: bool
    of tkNumber:
      numKind*: NumKind

  Lexer* = object
    source*: string
    data*: seq[Token]
    ok*: bool
    matchLen*, matchMax*: int

proc `$`(lexer: Lexer): string = 
  result = if lexer.ok: "Sucess" else: "Fail"
  result.add(&" {lexer.matchLen}/{lexer.matchMax}, Tokens: \n\t")
  for token in lexer.data:
    result.add(&"{token.lexeme}({token.kind}) ")

proc getCoord(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.len, lines[^1].len+1)

proc newTNull*(coord: Coord, lexeme = "null"): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkNull)

proc newTBool*(coord: Coord, lexeme: string): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkBool)

proc newTEqual*(coord: Coord, lexeme = "="): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkEqual)

proc newTIdent*(coord: Coord, lexeme: string): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkIdent)

proc newTNumber*(coord: Coord, lexeme: string, kind: NumKind): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkNumber, numKind: kind)

proc newTString*(coord: Coord, lexeme, val: string, raw: bool): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkString, strVal: val, raw: raw)

proc newTTypeAnnot*(coord: Coord, lexeme, val: string): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkTypeAnnot, typeAnnot: val)

proc newTOpenBlock*(coord: Coord, lexeme = "{"): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkOpenBlock)

proc newTCloseBlock*(coord: Coord, lexeme = "}"): Token = 
  Token(coord: coord, lexeme: lexeme, kind: tkCloseBlock)

grammar "common":
  escline <- '\\' * *ws * (singleLineComment | newline)

  linespace <- newline | ws | singleLineComment

  newline <- "\c" | "\l" | "\c\l" | "\u000C" | "\f" | "\u2028" | "\u2029"

  ws <- bom | unicodeSpace | multiLineComment

  bom <- "\uFEFF"

  unicodeSpace <- "\u0009" | "\u0020" | "\u00A0" | "\u1680" | "\u2000" | "\u200A" | "\u202F" | "\u205F" | "\u3000"

  eof <- !1

  singleLineComment <- "//" * +(1 - newline) * (newline | eof)
  multiLineComment <- "/*" * commentedBlock
  commentedBlock <- "*/" | (multiLineComment | '*' | '/' | +(1 - {'*', '/'})) * commentedBlock

  sign <- {'+', '-'}

  equal <- '=':
    lexer.data.add(newTEqual(lexer.source.getCoord(@0)))

  childrenOpen <- '{':
    lexer.data.add(newTOpenBlock(lexer.source.getCoord(@0)))

  childrenClose <- '}':
    lexer.data.add(newTCloseBlock(lexer.source.getCoord(@0)))

grammar "numbers":
  number <- hex | octal | binary | decimal

  decimal <- ?common.sign * integer * ?('.' * integer) * ?exponent:
    lexer.data.add(newTNumber(lexer.source.getCoord(@0), $0, nkDec))
  exponent <- i"e" * ?common.sign * integer
  integer <- Digit * *(Digit | '_')

  hex <- ?common.sign * "0x" * Xdigit * *(Xdigit | '_'):
    lexer.data.add(newTNumber(lexer.source.getCoord(@0), $0, nkHex))
  octal <- ?common.sign * "0o" * {'0'..'7'} * *{'0'..'7', '_'}:
    lexer.data.add(newTNumber(lexer.source.getCoord(@0), $0, nkOct))
  binary <- ?common.sign * "0b" * {'0', '1'} * *{'0', '1', '_'}:
    lexer.data.add(newTNumber(lexer.source.getCoord(@0), $0, nkBin))

grammar "strings":
  str <- rawString | escapedString
  escapedString <- '"' * >*character * '"':
    lexer.data.add(newTString(lexer.source.getCoord(@0), $0, $1, false))
  character <- '\\' * escape | (1 - {'\\', '"'})
  escape <- {'"', '\\', '/', 'b', 'f', 'n', 'r', 't'} | i"u" * '{' * Xdigit[1..6] * '}'

  rawString <- 'r' * rawStringHash
  rawStringHash <- R("hashes", *'#') * rawStringQuotes * R("hashes")
  rawStringQuotes <- '"' * >*(1 - ('"' * R("hashes"))) * '"':
    lexer.data.add(newTString(lexer.source.getCoord(@0), $0, $1, true))

const lexerPeg* = peg("nodes", lexer: Lexer):
  nodes <- *common.linespace * ?(node * ?nodes) * *common.linespace

  node <- slashDashComment * ?typeAnnotation * strOrIdent * *(+nodeSpace * nodePropOrArg) * ?(*nodeSpace * nodeChildren * *common.ws) * *nodeSpace * nodeTerminator
  nodePropOrArg <- slashDashComment * >+(1 - common.ws):
    echo $1
    echo "end"
  nodeChildren <- slashDashComment * common.childrenOpen * nodes * common.childrenClose
  nodeSpace <- *common.ws * common.escline * *common.ws | +common.ws
  nodeTerminator <- common.singleLineComment | common.newline | ';' | common.eof

  slashDashComment <- ?("/-" * *nodeSpace)

  strOrIdent <- strings.str | matchIdent

  matchIdent <- ident:
    lexer.data.add(newTIdent(lexer.source.getCoord(@0), $0))

  ident <- (startIdentifierChar * *identifierChar | common.sign * ?((identifierChar - Digit) * *identifierChar)) - keyword

  startIdentifierChar <- identifierChar - (Digit | common.sign)
  identifierChar <- 1 - (common.linespace | {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'})


  keyword <- boolean | null
  prop <- strOrIdent * common.equal * value
  value <- ?typeAnnotation * (strings.str | numbers.number | keyword)

  typeAnnotation <- '(' * >ident * ')':
    lexer.data.add(newTTypeAnnot(lexer.source.getCoord(@0), $0, $1))

  boolean <- ("true" | "false") * !identifierChar:
    lexer.data.add(newTBool(lexer.source.getCoord(@0), $0))

  null <- "null" * !identifierChar:
    lexer.data.add(newTNull(lexer.source.getCoord(@0)))

proc scanKDL*(source: string): Lexer = 
  result.source = source
  let res = lexerPeg.match(source, result)
  result.ok = res.ok and res.matchLen == res.matchMax 
  result.matchLen = res.matchLen
  result.matchMax = res.matchMax

echo scanKDL("""// Nodes can be separated into multiple lines
title \
  "Some title"


// Files must be utf8 encoded!
smile "😁"

// Instead of anonymous nodes, nodes and properties can be wrapped
// in "" for arbitrary node names.
"!@#$@$%Q#$%~@!40" "1.2.3" "!!!!!"=true

// The following is a legal bare identifier:
foo123~!@#$%^&*.:'|?+ "weeee"

// And you can also use unicode!
ノード　お名前="☜(ﾟヮﾟ☜)"

// kdl specifically allows properties and values to be
// interspersed with each other, much like CLI commands.
foo bar=true "baz" quux=false 1 2 3""")
