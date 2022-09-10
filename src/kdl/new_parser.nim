import std/[parseutils, strformat, strutils, unicode, tables]
import new_lexer, nodes

type
  KdlParserError* = object of KdlError

  Parser* = object
    source*: string
    stack*: seq[Token]
    current*: int

  Match[T] = tuple[ok: bool, val: T]

const
  numbers = {tkNumDec, tkNumHex, tkNumBin, tkNumOct}
  strings = {tkString, tkRawString}

proc eof(parser: Parser, extra = 0): bool = 
  parser.current + extra >= parser.stack.len

proc peek(parser: Parser, next = 0): Token = 
  if not parser.eof(next):
    result = parser.stack[parser.current + next]

proc error(parser: Parser, msg: string) = 
  let coord = parser.peek().coord
  raise newException(KdlParserError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{parser.source.errorAt(coord).indent(2)}")

proc consume(parser: var Parser, amount = 1) = 
  parser.current += amount

template valid(x: bool) = 
  when result is bool:
    result = x
  else:
    result.ok = x

  if not x:
    return

template invalid(x: bool) = 
  when result is bool:
    result = not x
  else:
    result.ok = not x

  if x:
    return

template valid[T](x: Match[T]): T = 
  when result is bool:
    result = x.ok
  else:
    result.ok = x.ok

  if not x.ok:
    return

  x.val

proc match(parser: var Parser, x: TokenKind | set[TokenKind], required = true): Match[Token] {.discardable.} = 
  let token = parser.peek()
  if (when x is TokenKind: token.kind == x else: token.kind in x):
    result.ok = true
    result.val = token
    parser.consume()
  elif required:
    when x is TokenKind:
      parser.error &"Expected {x} but found {token.kind}"
    else:
      parser.error &"Expected one of {x} but found {token.kind}"

proc skipWhile(parser: var Parser, kinds: set[TokenKind]) = 
  while not parser.eof():
    if parser.peek().kind in kinds:
      parser.consume()
    else:
      break

proc more(parser: var Parser, kind: TokenKind, required = true): bool {.discardable.} = 
  ## Matches one or more tokens of `kind`
  discard valid parser.match(kind, required)
  parser.skipWhile({kind})

proc parseNumber(token: Token): KdlVal = 
  assert token.kind in numbers

  result = initKNumber()

  result.num = 
    case token.kind
    of tkNumDec:
      token.lexeme.parseFloat()
    of tkNumBin:
      float token.lexeme.parseBinInt()
    of tkNumHex:
      float token.lexeme.parseHexInt()
    of tkNumOct:
      float token.lexeme.parseOctInt()
    else: 0f

proc escapeString(str: string, x = 0..str.high): string = 
  var i = x.a
  while i <= x.b:
    if str[i] == '\\':
      inc i # Consume backslash
      if str[i] == 'u':
        inc i, 2 # Consume u and opening {
        var hex: string
        inc i, str.parseWhile(hex, HexDigits, i)
        result.add Rune(parseHexInt(hex))
      else:
        result.add escapeTable[str[i]]
    else:
      result.add str[i]

    inc i

proc parseString(token: Token): KdlVal = 
  assert token.kind in strings

  result = initKString()

  if token.kind == tkString:
    result.str = escapeString(token.lexeme, 1..<token.lexeme.high) # Escape the string body, excluding the quotes
  else: # Raw string
    var hashes: string
    discard token.lexeme.parseUntil(hashes, '"', start = 1) # Count the number of hashes
    result.str = token.lexeme[2 + hashes.len..token.lexeme.high - hashes.len - 1] # Exlude the starting 'r' + hashes + '#' and ending '"' + hashes

proc parseBool(token: Token): KdlVal = 
  assert token.kind == tkBool
  initKBool(token.lexeme.parseBool())

proc parseNull(token: Token): KdlVal = 
  assert token.kind == tkNull
  initKNull()

proc parseValue(token: Token): KdlVal = 
  result = 
    case token.kind
    of numbers:
      token.parseNumber()
    of strings:
      token.parseString()
    of tkBool:
      token.parseBool()
    of tkNull:
      token.parseNull()
    else:
      token.parseNull()

proc parseIdent(token: Token): string = 
  case token.kind
  of strings:
    token.parseString().getString()
  of tkIdent:
    token.lexeme
  else:
    ""

proc matchIdent(parser: var Parser, required = true): Match[string] {.discardable.} = 
  # let temp = parser.match({tkIdent} + strings, required)
  # result.val = valid(temp).parseIdent()
  # assert result == (true, "node")

  result.val = valid(parser.match({tkIdent} + strings, required)).parseIdent()
  assert result == (false, "") # It doesn't even reach this part

proc matchTypeAnnot(parser: var Parser, required = true): Match[string] {.discardable.} = 
  discard valid parser.match(tkOpenType, required)
  result.val = valid(parser.matchIdent(true)).parseIdent()
  discard parser.match(tkCloseType, true)

proc matchValue(parser: var Parser, required = true): Match[KdlVal] {.discardable.} = 
  let (_, annot) = parser.matchTypeAnnot(false)
  let token = valid parser.match({tkBool, tkNull} + strings + numbers, required)

  result.val = token.parseValue()
  result.val.annot = annot

# proc parseProp(parser: Parser): KdlProp = 

proc matchProp(parser: var Parser, required = true): Match[KdlProp] {.discardable.} = 
  let ident = valid parser.matchIdent(required)
  discard valid parser.match(tkEqual, required)
  let value = valid parser.matchValue(required)

  result.val = initKProp(ident, value)

proc matchNodeEnd(parser: var Parser, required = true): bool {.discardable.} = 
  result = parser.eof()

  if not result:
    discard valid parser.match({tkNewLine, tkSemicolon}, required)

proc skipLineSpaces(parser: var Parser) = 
  parser.skipWhile({tkNewLine, tkWhitespace})

proc matchNode(parser: var Parser, required = true): Match[KdlNode] {.discardable.}

proc matchNodes(parser: var Parser, children = false): Match[KdlDoc] {.discardable.} = 
  parser.skipLineSpaces()
  while (let (ok, node) = parser.matchNode(false); ok):
    result.ok = true
    result.val.add node
    parser.skipLineSpaces()

proc matchChildren(parser: var Parser, required = true): Match[KdlDoc] {.discardable.} = 
  discard valid parser.match(tkOpenBlock, required)
  result.val = valid parser.matchNodes()
  discard valid parser.match(tkCloseBlock, true)

proc matchNode(parser: var Parser, required = true): Match[KdlNode] {.discardable.} = 
  let annot = parser.matchTypeAnnot(false).val
  let ident = valid parser.matchIdent(required)
  result.val = initKNode(ident, annot = annot)

  invalid parser.matchNodeEnd(false)

  valid parser.more(tkWhitespace, required)

  while true: # Match arguments and properties
    if (let (ok, prop) = parser.matchProp(false); ok):
      result.val.props.add prop
    else:
      if (let (ok, val) = parser.matchValue(false); ok):
        result.val.args.add val
      else:
        break

    valid not parser.matchNodeEnd(false)

    valid parser.more(tkWhitespace, required)

  result.val.children = parser.matchChildren(false).val

  valid not parser.matchNodeEnd(required)

proc parseKdl*(lexer: Lexer): KdlDoc = 
  var parser = Parser(stack: lexer.stack, source: lexer.source)
  result = parser.matchNodes().val

proc parseKdl*(source: string, start = 0): KdlDoc = 
  source.scanKdl().parseKdl()

proc parseKdlFile*(path: string): KdlDoc = 
  parseKdl(readFile(path))

echo parseKdl("node")
