import std/[parseutils, strformat, strutils, unicode, options, streams, tables, macros]
import lexer, nodes, types, utils

type
  None = object

  Parser* = object
    case runtime*: bool
    of true:
      stream*: Stream
    else:
      source*: string
    stack*: seq[Token]
    current*: int

  Match[T] = tuple[ok, ignore: bool, val: T]

const
  numbers = {tkNumFloat, tkNumInt, tkNumHex, tkNumBin, tkNumOct}
  intNumbers = numbers - {tkNumFloat}
  strings = {tkString, tkRawString}

macro parsing(x: typedesc, body: untyped): untyped = 
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() {.parsing[T].} = 
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(parser: var Parser, required: bool = true): Match[T] {.discardable.} = 
  ##   let before = getPos(parser)
  ##   echo "hi"
  ## ```

  body.expectKind(nnkProcDef)

  result = body.copyNimTree()

  result.params[0] = nnkBracketExpr.newTree(ident"Match", x) # Return type
  result.params.insert(1, newIdentDefs(ident"parser", newNimNode(nnkVarTy).add(ident"Parser")))
  result.params.add(newIdentDefs(ident"required", ident"bool", newLit(true)))

  result.addPragma(ident"discardable")

  if result[^1].kind == nnkStmtList: 
    result[^1].insert(0, quote do: 
      let before {.inject.} = parser.current
    )

proc eof(parser: Parser, extra = 0): bool = 
  parser.current + extra >= parser.stack.len

proc peek(parser: Parser, next = 0): Token = 
  if not parser.eof(next):
    result = parser.stack[parser.current + next]
  else:
    let token = parser.stack[parser.current - 1]
    result = Token(start: token.start + token.lexeme.len)

proc error(parser: Parser, msg: string) = 
  let coord = 
    if parser.runtime:
      parser.stream.getCoord(parser.peek().start)
    else:
      parser.source.getCoord(parser.peek().start)

  let errorMsg = 
    if parser.runtime:
      parser.stream.errorAt(coord)
    else:
      parser.source.errorAt(coord)

  raise newException(KdlParserError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{errorMsg.indent(2)}\n")

proc consume(parser: var Parser, amount = 1) = 
  parser.current += amount

template invalid[T](x: Match[T]) = 
  ## Returns if x is ok
  let val = x

  result.ok = val.ok

  if val.ok:
    return

template valid[T](x: Match[T]): T = 
  ## Returns if x is not ok and gives x.val back
  let val = x

  result.ok = val.ok

  if not val.ok:
    result.ignore = false
    parser.current = before
    return

  val.val

template hasValue[T](match: Match[T]): bool = 
  let (ok, ignore, val {.inject.}) = match; ok and not ignore

template setValue[T](x: untyped, match: Match[T]) = 
  if hasValue match:
    x = val

proc match(x: TokenKind | set[TokenKind]) {.parsing: Token.} = 
  let token = parser.peek()
  let matches =
    when x is TokenKind:
     token.kind == x
   else:
     token.kind in x
  
  if matches:
    result.ok = true
    result.val = token
    parser.consume()
  elif required:
    when x is TokenKind:
      parser.error &"Expected {x} but found {token.kind}"
    else:
      parser.error &"Expected one of {x} but found {token.kind}"

proc skipWhile(parser: var Parser, kinds: set[TokenKind]): int {.discardable.} = 
  while not parser.eof():
    if parser.peek().kind in kinds:
      parser.consume()
      inc result
    else:
      break

proc more(kind: TokenKind) {.parsing: None.} = 
  ## Matches one or more tokens of `kind`
  discard valid parser.match(kind, required)
  discard parser.skipWhile({kind})

proc parseNumber(token: Token): KdlVal = 
  assert token.kind in numbers

  if token.kind in intNumbers:
    result = initKInt()

    result.num = 
      case token.kind
      of tkNumInt:
        token.lexeme.parseBiggestInt()
      of tkNumBin:
        token.lexeme.parseBinInt()
      of tkNumHex:
        token.lexeme.parseHexInt()
      of tkNumOct:
        token.lexeme.parseOctInt()
      else: 0

  else:
    result = initKFloat()
    result.fnum = token.lexeme.parseFloat()

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

proc skipLineSpaces(parser: var Parser) = 
  parser.skipWhile({tkNewLine, tkWhitespace})

proc matchLineCont() {.parsing: None.} = 
  parser.skipWhile({tkWhitespace})
  discard valid parser.match(tkLineCont, required)
  discard parser.skipWhile({tkWhitespace})

proc matchNodeSpace() {.parsing: None.} = 
  invalid parser.matchLineCont(required = false)
  discard valid parser.more(tkWhitespace, required)

proc matchSlashDash() {.parsing: None.} = 
  discard valid parser.match(tkSlashDash, required)
  while parser.matchNodeSpace(required = false).ok: discard 

proc matchIdent() {.parsing: Option[string].} = 
  result.val = valid(parser.match({tkIdent} + strings, required)).parseIdent()

proc matchTag() {.parsing: Option[string].} = 
  discard valid parser.match(tkOpenPar, required)
  result.val = valid parser.matchIdent(required = true)
  discard parser.match(tkClosePar, true)

proc matchValue(slashdash = false) {.parsing: KdlVal.} = 
  if slashdash:
    result.ignore = parser.matchSlashDash(required = false).ok

  let (_, _, tag) = parser.matchTag(required = false)

  result.val = valid(parser.match({tkBool, tkNull} + strings + numbers, required)).parseValue()
  result.val.tag = tag

proc matchProp(slashdash = true) {.parsing: KdlProp.} = 
  if slashdash:
    result.ignore = parser.matchSlashDash(required = false).ok

  let ident = valid parser.matchIdent(required = false)

  discard valid parser.match(tkEqual, required)

  let value = valid parser.matchValue(required = true)

  result.val = (ident.get, value)

proc matchNodeEnd() {.parsing: None.} = 
  result.ok = parser.eof()

  if not result.ok:
    let token = parser.peek()
    discard valid parser.match({tkNewLine, tkSemicolon, tkCloseBra}, required)

    if token.kind == tkCloseBra: # Unconsume
      dec parser.current

proc matchNode(slashdash = true) {.parsing: KdlNode.}

proc matchNodes() {.parsing: KdlDoc.} = 
  parser.skipLineSpaces()

  while not parser.eof():
    if hasValue parser.matchNode(required = required):
      result.ok = true
      result.val.add val

    elif not required: break

    parser.skipLineSpaces()

proc matchChildren(slashdash = true) {.parsing: KdlDoc.} = 
  if slashdash:
    result.ignore = parser.matchSlashDash(required = false).ok

  discard valid parser.match(tkOpenBra, required)
  result.val = parser.matchNodes(required = false).val
  discard valid parser.match(tkCloseBra, true)

proc matchNode(slashdash = true) {.parsing: KdlNode.} = 
  if slashdash:
    result.ignore = parser.matchSlashDash(required = false).ok

  let tag = parser.matchTag(required = false).val
  let ident = valid parser.matchIdent(required)

  result.val = initKNode(ident.get, tag = tag)

  invalid parser.matchNodeEnd(required = false)

  discard valid parser.matchNodeSpace(required = true)

  while true: # Match arguments and properties
    let propMatch = parser.matchProp(required = false)

    if hasValue propMatch:
      result.val.props[val.key] = val.val
    else:
      let valMatch = parser.matchValue(required = false, slashdash = true)
      if hasValue valMatch:
        result.val.args.add val
      elif not valMatch.ignore and not propMatch.ignore:
        break

    if parser.match(tkOpenBra, required = false).ok: # Children trailing: node 1 2{}
      dec parser.current # Unconsume the open bracket
      break
    elif not parser.matchNodeSpace(required = false).ok:
      invalid parser.matchNodeEnd(required = true)

  setValue result.val.children, parser.matchChildren(required = false)

  invalid parser.matchNodeEnd(required = true)

proc parseKdl*(lexer: sink Lexer): KdlDoc = 
  if lexer.runtime:
    var parser = Parser(runtime: true, stack: lexer.stack, stream: lexer.stream)
    defer: parser.stream.close()
    result = parser.matchNodes().val
  else:
    var parser = Parser(runtime: false, stack: lexer.stack, source: lexer.source)
    result = parser.matchNodes().val    

proc parseKdl*(source: string, start = 0): KdlDoc = 
  var lexer = Lexer(runtime: false, source: source, current: start)
  lexer.scanKdl()
  result = lexer.parseKdl()

proc parseKdlFile*(path: string): KdlDoc = 
  parseKdl(readFile(path))

proc parseKdl*(stream: sink Stream): KdlDoc = 
  var lexer = Lexer(runtime: true, stream: stream)
  lexer.scanKdl()
  result = lexer.parseKdl()

proc parseKdlStream*(source: sink string): KdlDoc = 
  parseKdl(newStringStream(source))

proc parseKdlFileStream*(path: string): KdlDoc = 
  parseKdl(newFileStream(path))
