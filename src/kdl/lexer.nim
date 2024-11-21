import std/[strformat, strutils, unicode, streams, tables, macros]
import utils, types

type
  TokenKind* = enum
    tkEmpty = "empty"
    tkNull = "null"
    tkStar = "star"
    tkPlus = "plus"
    tkBool = "bool"
    tkTilde = "tilde"
    tkComma = "comma"
    tkCaret = "caret"
    tkDollar = "dollar"
    tkSemicolon = "semicolon"
    tkGreater = "greater_than"
    tkSlashDash = "slash_dash"
    tkDoublePipe = "double_pipe"
    tkLineCont = "line_continuation"
    tkEqual = "equal"
    tkIdent = "identifier"
    tkString = "string"
    tkRawString = "raw_string"
    tkWhitespace = "whitespace"
    tkNewLine = "new_line"
    tkOpenPar = "open_parenthesis"
    tkClosePar = "close_parenthesis" # Type tagation
    tkOpenBra = "open_bracket"
    tkCloseBra = "close_bracket" # Children block
    tkOpenSqu = "open_square_bracket"
    tkCloseSqu = "close_square_bracket"
    tkNumFloat = "float_number"
    tkNumInt = "integer_number"
    tkNumHex = "hexadecimal_number"
    tkNumBin = "binary_number"
    tkNumOct = "octagonal_number"

  Token* = object
    lexeme*: string
    start*: int
    kind*: TokenKind

  Lexer* = object
    case isStream*: bool
    of true:
      stream*: Stream
    else:
      source*: string
      current*: int
    multilineStringsNewLines*: seq[tuple[idx, length: int]]
      # Indexes and length of new lines in multiline strings that have to be converted to a single \n
    stack*: seq[Token]

const
  nonIdenChars = {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'}
  nonInitialChars = Digits + nonIdenChars
  whitespaces = [
    0x0009, 0x0020, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
    0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000,
  ]
  equals = [0x003D, 0xFE66, 0xFF1D, 0x1F7F0]
  litMatches = {
    "*": tkStar,
    "+": tkPlus,
    "~": tkTilde,
    "^": tkCaret,
    ",": tkComma,
    "$": tkDollar,
    ">": tkGreater,
    "null": tkNull,
    "true": tkBool,
    "false": tkBool,
    ";": tkSemicolon,
    "/-": tkSlashDash,
    "||": tkDoublePipe,
    "(": tkOpenPar,
    ")": tkClosePar,
    "{": tkOpenBra,
    "}": tkCloseBra,
    "[": tkOpenSqu,
    "]": tkCloseSqu,
  }

proc `$`*(lexer: Lexer): string =
  result =
    if lexer.isStream:
      &"{(if lexer.stream.atEnd: \"SUCCESS\" else: \"FAIL\")}\n\t"
    else:
      &"{(if lexer.current == lexer.source.len: \"SUCCESS\" else: \"FAIL\")} {lexer.current}/{lexer.source.len}\n\t"

  for token in lexer.stack:
    result.add &"({token.kind})"
    result.addQuoted token.lexeme
    result.add " "

proc getPos*(lexer: Lexer): int =
  if lexer.isStream:
    lexer.stream.getPosition()
  else:
    lexer.current

proc setPos(lexer: var Lexer, x: int) =
  if lexer.isStream:
    lexer.stream.setPosition(x)
  else:
    lexer.current = x

proc inc(lexer: var Lexer, x = 1) =
  lexer.setPos(lexer.getPos() + x)

proc dec(lexer: var Lexer, x = 1) =
  lexer.setPos(lexer.getPos() - x)

macro lexing(token: TokenKind, body: untyped) =
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() {.lexing: tkEmpty.} =
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(lexer: var Lexer, consume: bool = true, addToStack: bool = true): bool {.discardable.} =
  ##   let before = getPos(lexer)
  ##   echo "hi"
  ##   result = before != getPos(lexer)
  ##   if not consume:
  ##     setPos(lexer, before)
  ##   if result and addToStack: # Only when token is not tkEmpty
  ##     lexer.add(token, before)
  ## ```

  body.expectKind(nnkProcDef)

  body.params[0] = ident"bool" # Return type
  body.params.add(newIdentDefs(ident"lexer", newNimNode(nnkVarTy).add(ident"Lexer")))
  body.params.add(newIdentDefs(ident"consume", ident"bool", newLit(true)))
  body.params.add(newIdentDefs(ident"addToStack", ident"bool", newLit(true)))

  body.addPragma(ident"discardable")

  # Modify the procedure statements list (body)

  body[^1].insert(
    0,
    quote do:
      let before {.inject.} = getPos(lexer),
  )
  body[^1].add(
    quote do:
      result = before != getPos(lexer)
  )
  body[^1].add(
    quote do:
      if not consume:
        setPos(lexer, before)
  )

  if token != bindSym"tkEmpty":
    body[^1].add(
      quote do:
        if result and addToStack:
          lexer.add(`token`, before)
    )

  result = body

proc eof(lexer: var Lexer, extra = 0): bool =
  let before = lexer.getPos
  inc lexer, extra

  result =
    if lexer.isStream:
      lexer.stream.atEnd
    else:
      lexer.current >= lexer.source.len

  lexer.setPos before

proc peek(lexer: var Lexer, next = 0): char =
  if not lexer.eof(next):
    let before = lexer.getPos
    inc lexer, next

    result =
      if lexer.isStream:
        lexer.stream.peekChar()
      else:
        lexer.source[lexer.current]

    lexer.setPos before

proc peekStr(lexer: var Lexer, until: int): string =
  if lexer.eof(until - 1):
    return

  if lexer.isStream:
    lexer.stream.peekStr(until)
  else:
    lexer.source[lexer.current ..< lexer.current + until]

proc peek(lexer: var Lexer, x: string): bool =
  lexer.peekStr(x.len) == x

proc peekRune(lexer: var Lexer): Rune =
  if lexer.eof():
    return

  if lexer.isStream:
    lexer.stream.peekRune()
  else:
    lexer.source.runeAt(lexer.current)

proc add(lexer: var Lexer, kind: TokenKind, start: int) =
  let before = lexer.getPos()
  lexer.setPos start
  lexer.stack.add(
    Token(kind: kind, lexeme: lexer.peekStr(before - start), start: start)
  )
  lexer.setPos before

proc error(lexer: Lexer, msg: string) =
  let coord =
    if lexer.isStream:
      lexer.stream.getCoord(lexer.getPos)
    else:
      lexer.source.getCoord(lexer.getPos)

  let errorMsg =
    if lexer.isStream:
      lexer.stream.errorAt(coord)
    else:
      lexer.source.errorAt(coord)

  raise newException(
    KdlLexerError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{errorMsg.indent(2)}\n"
  )

proc literal(lexer: var Lexer, lit: string, consume = true): bool {.discardable.} =
  result = lexer.peek(lit)
  if result and consume:
    lexer.inc lit.len

proc skipWhile(lexer: var Lexer, x: set[char]): int {.discardable.} =
  while not lexer.eof() and lexer.peek() in x:
    inc result
    inc lexer

proc disallowedRunes() {.lexing: tkEmpty.} =
  let r = lexer.peekRune.int32
  if r == 0xFEFFi32:
    if lexer.getPos() == 0:
      lexer.inc 0xFEFF.Rune.size
    else:
      lexer.error &"The code point U+{r.toHex(4)} is only allowed at the start of a KDL document. Not"
  elif isDisallowedRune(r):
    lexer.error &"The code point U+{r.toHex(4)} isn't allowed on a KDL document"

proc tokenNewLine*() {.lexing: tkNewLine.} =
  for nl in newLines:
    if lexer.peek(nl):
      lexer.inc nl.len
      break

proc tokenNumWhole() {.lexing: tkEmpty.} =
  if lexer.peek() in {'-', '+'}:
    inc lexer

  if lexer.peek() notin Digits:
    lexer.setPos before
    return

  inc lexer

  lexer.skipWhile(Digits + {'_'})

proc tokenNumExp() {.lexing: tkEmpty.} =
  if lexer.peek().toLowerAscii() != 'e':
    return

  inc lexer

  if lexer.peek() in {'-', '+'}:
    inc lexer

  if lexer.peek() notin Digits:
    lexer.error "Expected one or more digits"

  lexer.skipWhile(Digits + {'_'})

proc tokenNumFloat() {.lexing: tkNumFloat.} =
  if not lexer.tokenNumWhole():
    lexer.setPos before
    return

  if lexer.peek() == '.':
    inc lexer

    if lexer.peek() notin Digits:
      lexer.error "Expected one or more digits"

    lexer.skipWhile(Digits + {'_'})

    if lexer.peek().toLowerAscii() == 'e':
      lexer.tokenNumExp()
  elif lexer.peek().toLowerAscii() == 'e':
    lexer.tokenNumExp()
  else:
    lexer.setPos before
    return

proc tokenNumInt*() {.lexing: tkNumInt.} =
  lexer.tokenNumWhole()

proc tokenNumBin*() {.lexing: tkNumBin.} =
  if lexer.peek("0b"):
    lexer.inc 2
    if lexer.peek() notin {'0', '1'}:
      lexer.error "Expected one or more binary digits"

    lexer.skipWhile({'0', '1', '_'})

proc tokenNumHex*() {.lexing: tkNumHex.} =
  if lexer.peek("0x"):
    lexer.inc 2
    if lexer.peek() notin HexDigits:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile(HexDigits + {'_'})

proc tokenNumOct*() {.lexing: tkNumOct.} =
  if lexer.peek("0o"):
    lexer.inc 2
    if lexer.peek() notin {'0' .. '7'}:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile({'0' .. '7', '_'})

proc getCoord(lexer: Lexer, pos = lexer.getPos()): Coord =
  if lexer.isStream:
    lexer.stream.getCoord(pos)
  else:
    lexer.source.getCoord(pos)

proc tokenEqual() {.lexing: tkEqual.} =
  if (let r = lexer.peekRune(); r.int32 in equals):
    lexer.inc r.size

proc tokenStringBody(lexer: var Lexer, raw = false) =
  let before = lexer.getPos()

  if raw:
    if lexer.peek() != 'r':
      return

    inc lexer

  let hashes = lexer.skipWhile({'#'})

  if lexer.peek() != '"':
    lexer.setPos before
    return

  inc lexer

  var terminated = false

  while not lexer.eof():
    lexer.disallowedRunes()
    let before = lexer.getPos()
    if lexer.tokenNewLine(addToStack = false):
      lexer.multilineStringsNewLines.add((before, lexer.getPos() - before))
      continue

    let r = lexer.peekRune()
    case r
    of '\\'.Rune:
      if raw:
        inc lexer
        continue

      let next = lexer.peek(1)
      if next notin escapeTable and next != 'u':
        lexer.error &"Invalid escape '{next}'"

      lexer.inc 2

      if next == 'u':
        if lexer.peek() != '{':
          lexer.error "Expected opening bracket '{'"

        inc lexer

        let digits = lexer.skipWhile(HexDigits)
        if digits notin 1 .. 6:
          lexer.error &"Expected 1-6 hexadecimal digits but found {digits}"

        if lexer.peek() != '}':
          lexer.error "Expected closing bracket '}'"
    of '"'.Rune:
      inc lexer
      let endHashes = lexer.skipWhile({'#'})
      if not raw or hashes == 0 or endHashes == hashes:
        terminated = true
        break
      elif endHashes > hashes:
        lexer.error &"Expected {hashes} hashes but found {endHashes}"
    else:
      lexer.disallowedRunes()
      inc lexer

  if not terminated:
    lexer.error "Unterminated string"

proc tokenString*() {.lexing: tkString.} =
  lexer.tokenStringBody()

proc tokenRawString*() {.lexing: tkRawString.} =
  lexer.tokenStringBody(raw = true)

proc tokenMultiLineComment*() {.lexing: tkEmpty.} =
  if not lexer.peek("/*"):
    return

  lexer.inc 2

  var nested = 1

  while not lexer.eof() and nested > 0:
    if lexer.peek("*/"):
      dec nested
      lexer.inc 2
    elif lexer.peek("/*"):
      inc nested
      lexer.inc 2
    else:
      inc lexer

  if nested > 0:
    lexer.error "Expected end of multi-line comment"

proc tokenWhitespace*() {.lexing: tkWhitespace.} =
  if not lexer.eof() and (let rune = lexer.peekRune(); rune.int in whitespaces):
    lexer.inc rune.size
  else:
    lexer.tokenMultiLineComment()

proc skipWhitespaces*() {.lexing: tkEmpty.} =
  while lexer.tokenWhitespace():
    discard

proc tokenIdent*() {.lexing: tkIdent.} =
  if lexer.eof() or lexer.peek() in nonInitialChars:
    return

  # Check the identifier is similar to a boolean, null or number, and if it is it should follow the EOF, a whitespace, a new line or any non-ident char in order to be discarded.
  if (
    lexer.literal("true") or lexer.literal("false") or lexer.literal("null") or
    lexer.tokenNumHex(addToStack = false) or lexer.tokenNumBin(addToStack = false) or
    lexer.tokenNumOct(addToStack = false) or lexer.tokenNumFloat(addToStack = false) or
    lexer.tokenNumInt(addToStack = false)
  ):
    if (
      lexer.eof() or lexer.tokenWhitespace(addToStack = false) or
      lexer.tokenNewLine(addToStack = false) or lexer.peek() in nonIdenChars
    ):
      return

  block outer:
    while not lexer.eof() or not lexer.tokenWhitespace(consume = false) or
        not lexer.tokenNewLine(consume = false):
      lexer.disallowedRunes()
      let rune = lexer.peekRune()
      if rune.int <= 0x20 or rune.int > 0x10FFFF:
        break

      for c in nonIdenChars:
        if rune == Rune(c):
          break outer

      lexer.inc rune.size

proc tokenSingleLineComment*() {.lexing: tkEmpty.} =
  if not lexer.peek("//"):
    return

  lexer.inc 2

  while not lexer.eof(): # Consume until a new line or EOF
    if lexer.tokenNewLine(addToStack = addToStack):
      break

    inc lexer

proc tokenLineCont*() {.lexing: tkLineCont.} =
  if lexer.peek() != '\\':
    return

  inc lexer

  lexer.skipwhitespaces()
  if not lexer.tokenSingleLineComment(addToStack = false) and
      not lexer.tokenNewLine(addToStack = false):
    lexer.error "Expected a new line"

proc tokenLitMatches() {.lexing: tkEmpty.} =
  ## Tries to match any of the litMatches literals.
  for (lit, kind) in litMatches:
    if lexer.literal(lit):
      lexer.add(kind, before)
      break

proc validToken*(
    source: sink string,
    token: proc(lexer: var Lexer, consume = true, addToStack = true): bool,
): bool =
  var lexer = Lexer(isStream: true, stream: newStringStream(source))

  try:
    result = lexer.token() and lexer.eof()
  except KdlLexerError:
    return

proc scanKdl*(lexer: var Lexer) =
  const choices = [
    tokenWhitespace, tokenNewLine, tokenLineCont, tokenSingleLineComment, tokenEqual,
    tokenRawString, tokenString, tokenIdent, tokenNumHex, tokenNumBin, tokenNumOct,
    tokenNumFloat, tokenNumInt, tokenLitMatches,
  ]

  while not lexer.eof():
    var anyMatch = false

    for choice in choices:
      if lexer.choice():
        anyMatch = true
        break

    if not anyMatch:
      lexer.error &"Could not match any pattern for {quoted($lexer.peekRune)}"

proc scanKdl*(source: string, start = 0): Lexer =
  result = Lexer(isStream: false, source: source, current: start)
  result.scanKdl()

proc scanKdlFile*(path: string): Lexer =
  scanKdl(readFile(path))

proc scanKdl*(stream: sink Stream): Lexer =
  result = Lexer(isStream: true, stream: stream)
  defer:
    result.stream.close()
  result.scanKdl()

proc scanKdlStream*(source: sink string): Lexer =
  scanKdl(newStringStream(source))

proc scanKdlFileStream*(path: string): Lexer =
  scanKdl(openFileStream(path))
