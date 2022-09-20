import std/[parseutils, strformat, strutils, unicode, options, tables, macros]
import lexer, nodes

type
  None = distinct void

  Parser* = object
    source*: string
    stack*: seq[Token]
    current*: int

  Match[T] = tuple[ok, ignore: bool, val: T]

const
  numbers = {tkNumDec, tkNumHex, tkNumBin, tkNumOct}
  strings = {tkString, tkRawString}

proc parsing(x: NimNode, slashdash: bool, body: NimNode): NimNode = 
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() {.parsing[T].} = 
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(parser: var Parser, required: bool = true, slashdash: bool = true): Match[T] {.discardable.} = 
  ##   result.ignore = parser.matchSlashDash(false).ok
  ##   echo "hi"
  ## ```

  body.expectKind(nnkProcDef)

  result = body.copyNimTree()

  result.params[0] = nnkBracketExpr.newTree(ident"Match", x) # Return type
  result.params.insert(1, newIdentDefs(ident"parser", newNimNode(nnkVarTy).add(ident"Parser")))
  result.params.add(newIdentDefs(ident"required", ident"bool", newLit(true)))
  result.params.add(newIdentDefs(ident"slashdash", ident"bool", newLit(slashdash)))

  result.addPragma(ident"discardable")

  if result[^1].kind == nnkEmpty:
    result[^1] = newStmtList()

  result[^1].insert(0, quote do:
    if slashdash:
      result.ignore = parser.matchSlashDash(false).ok
  )

macro parsing(x: typedesc, body: untyped): untyped = 
  parsing(x, false, body)

macro parsing(x: typedesc, slashdash: static bool, body: untyped): untyped = 
  parsing(x, slashdash, body)

proc matchSlashDash() {.parsing: None.}

proc eof(parser: Parser, extra = 0): bool = 
  parser.current + extra >= parser.stack.len

proc peek(parser: Parser, next = 0): Token = 
  if not parser.eof(next):
    result = parser.stack[parser.current + next]
  else:
    let token = parser.stack[parser.current - 1]
    result = Token(coord: (token.coord.line, token.coord.col + token.lexeme.len))

proc error(parser: Parser, msg: string) = 
  let coord = parser.peek().coord
  raise newException(KdlParserError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{parser.source.errorAt(coord).indent(2)}")

proc consume(parser: var Parser, amount = 1) = 
  parser.current += amount

template invalid[T](x: Match[T]) = 
  let val = x

  result.ok = val.ok

  when declared(slashDashComment):
    if slashDashComment:
      result.ok = false

  if val.ok:
    return

template valid[T](x: Match[T]): T = 
  let val = x

  result.ok = val.ok

  when declared(slashDashComment):
    if slashDashComment:
      result.ok = false

  if not result.ok:
    return

  val.val

template hasValue[T](match: Match[T]): bool = 
  let (ok, ignore, val {.inject.}) = match; ok and not ignore

template setValue[T](x: untyped, match: Match[T]) = 
  if hasValue match:
    x = val

proc match(x: TokenKind | set[TokenKind]) {.parsing: Token.} = 
  let token = parser.peek()

  # echo token, " in ", x, " == ", (when x is TokenKind: token.kind == x else: token.kind in x)
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

proc more(kind: TokenKind) {.parsing: None.} = 
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

proc parseIdent(token: Token): Option[string] = 
  case token.kind
  of strings:
    token.parseString().getString().some
  of tkIdent:
    token.lexeme.some
  else:
    string.none

proc matchSlashDash() {.parsing: None.} = 
  discard valid parser.match(tkSlashDash, required)
  parser.skipWhile({tkWhitespace})

proc matchIdent() {.parsing: Option[string].} = 
  result.val = valid(parser.match({tkIdent} + strings, required)).parseIdent()

proc matchTypeAnnot() {.parsing: Option[string].} = 
  discard valid parser.match(tkOpenType, required)
  result.val = valid parser.matchIdent(true)
  discard parser.match(tkCloseType, true)

proc matchValue() {.parsing: KdlVal.} = 
  let (_, _, annot) = parser.matchTypeAnnot(false)

  result.val = valid(parser.match({tkBool, tkNull} + strings + numbers, required)).parseValue()
  result.val.annot = annot

proc matchProp() {.parsing(KdlProp, true).} = 
  let ident = valid parser.matchIdent(required)
  if not parser.match(tkEqual, false).ok:
    dec parser.current # Unconsume identifier
    result.ok = false
    return

  let value = valid parser.matchValue(true)

  result.val = (ident.get, value)

proc matchNodeEnd() {.parsing: None.} = 
  result.ok = parser.eof()

  if not result.ok:
    let token = parser.peek()
    discard valid parser.match({tkNewLine, tkSemicolon, tkCloseBlock}, required)

    if token.kind == tkCloseBlock: # Unconsume
      dec parser.current

proc skipLineSpaces(parser: var Parser) = 
  parser.skipWhile({tkNewLine, tkWhitespace})

proc matchNode() {.parsing(KdlNode, true).}

proc matchNodes() {.parsing: KdlDoc.} = 
  parser.skipLineSpaces()

  while not parser.eof():
    if hasValue parser.matchNode(required):
      result.ok = true
      result.val.add val

    elif not required: break

    parser.skipLineSpaces()

proc matchChildren() {.parsing(KdlDoc, true).} = 
  discard valid parser.match(tkOpenBlock, required)
  result.val = parser.matchNodes(false).val
  discard valid parser.match(tkCloseBlock, true)

proc matchNode() {.parsing(KdlNode, true).} = 
  let annot = parser.matchTypeAnnot(false).val
  let ident = valid parser.matchIdent(required)

  result.val = initKNode(ident.get, annot = annot)

  invalid parser.matchNodeEnd(false)

  discard valid parser.more(tkWhitespace, true)

  while true: # Match arguments and properties
    if hasValue parser.matchProp(false):
      result.val.props[val.key] = val.val
    else:
      if hasValue parser.matchValue(false, slashdash = true):
        result.val.args.add val
      else:
        break

    invalid parser.matchNodeEnd(false)

    discard valid parser.more(tkWhitespace, true)

  setValue result.val.children, parser.matchChildren(false)
  # if hasValue parser.matchChildren(false):
    # result.val.children = val

  invalid parser.matchNodeEnd(true)

proc parseKdl*(lexer: Lexer): KdlDoc = 
  var parser = Parser(stack: lexer.stack, source: lexer.source)
  result = parser.matchNodes().val

proc parseKdl*(source: string, start = 0): KdlDoc = 
  source.scanKdl().parseKdl()

proc parseKdlFile*(path: string): KdlDoc = 
  parseKdl(readFile(path))
