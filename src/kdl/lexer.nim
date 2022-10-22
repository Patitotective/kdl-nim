import std/[strformat, strutils, unicode, streams, tables, macros]
import utils, types

type
  TokenKind* = enum
    tkEmpty = "empty", 
    tkNull = "null", 
    tkStar = "star", 
    tkPlus = "plus", 
    tkBool = "bool", 
    tkTilde = "tilde", 
    tkComma = "comma", 
    tkCaret = "caret", 
    tkDollar = "dollar", 
    tkIdent = "identifier", 
    tkSemicolon = "semicolon", 
    tkGreater = "greater_than", 
    tkSlashDash = "slash_dash", 
    tkDoublePipe = "double_pipe", 
    tkLineCont = "line_continuation"
    tkEqual = "equal", tkNotEqual = "not_equal", 
    tkString = "string", tkRawString = "raw_string", 
    tkWhitespace = "whitespace", tkNewLine = "new_line", 
    tkOpenPar = "open_parenthesis", tkClosePar = "close_parenthesis", # Type tagation
    tkOpenBra = "open_bracket", tkCloseBra = "close_bracket", # Children block
    tkOpenSqu = "open_square_bracket", tkCloseSqu = "close_square_bracket", 
    tkNumFloat = "float_number", tkNumInt = "integer_number", tkNumHex = "hexadecimal_number", tkNumBin = "binary_number", tkNumOct = "octagonal_number", 

  Token* = object
    lexeme*: string
    start*: int
    kind*: TokenKind

  Lexer* = object
    stream*: Stream
    stack*: seq[Token]

const
  nonIdenChars = {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'}
  nonInitialChars = Digits + nonIdenChars
  whitespaces = {0x0009, 0x0020, 0x00A0, 0x1680, 0x2000..0x200A, 0x202F, 0x205F, 0x3000}
  newLines = ["\c\l", "\r", "\n", "\u0085", "\f", "\u2028", "\u2029"]
  escapeTable* = {
    'n': "\u000A", # Line Feed
    'r': "\u000D", # Carriage Return
    't': "\u0009", # Character Tabulation (Tab)
    '\\': "\u005C", # Reverse Solidus (Backslash)
    '/': "\u002F", # Solidus (Forwardslash)
    '"': "\u0022", # Quotation Mark (Double Quote)
    'b': "\u0008", # Backspace
    'f': "\u000C", # Form Feed
    'u': "", # Unicode
  }.toTable

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
    "=": tkEqual, "!=": tkNotEqual, 
    "(": tkOpenPar, ")": tkClosePar,
    "{": tkOpenBra, "}": tkCloseBra, 
    "[": tkOpenSqu, "]": tkCloseSqu,
  }

proc `$`*(lexer: Lexer): string = 
  result = &"{(if lexer.stream.atEnd: \"SUCCESS\" else: \"FAIL\")}\n\t"
  for token in lexer.stack:
    result.addQuoted(token.lexeme)
    result.add(&"({token.kind}) ")

proc getPos*(lexer: Lexer): int = 
  lexer.stream.getPos()

proc setPos*(lexer: Lexer, x: int) = 
  lexer.stream.setPos(x)

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

  body[^1].insert(0, quote do:
    let before {.inject.} = getPos(lexer)
  )
  body[^1].add(quote do:
    result = before != getPos(lexer)
  )
  body[^1].add(quote do:
    if not consume:
      setPos(lexer, before)
  )

  if token != bindSym"tkEmpty":
    body[^1].add(quote do:
      if result and addToStack:
        lexer.add(`token`, before)
    )

  result = body

proc add(lexer: var Lexer, kind: TokenKind, start: int) = 
  let before = lexer.getPos()
  lexer.setPos start
  lexer.stack.add(Token(kind: kind, lexeme: lexer.stream.peekStr(before - start), start: start))
  lexer.setPos before

proc eof(lexer: Lexer, extra = 0): bool = 
  let before = lexer.getPos
  inc lexer.stream, extra 

  result = lexer.stream.atEnd

  lexer.setPos before

proc peek(lexer: Lexer, next = 0): char = 
  if not lexer.eof(next):
    let before = lexer.getPos
    inc lexer.stream, next

    result = lexer.stream.peekChar()

    lexer.setPos before

proc peek(lexer: Lexer, x: string): bool = 
  if not lexer.eof(x.high):
    result = lexer.stream.peekStr(x.len) == x

proc error(lexer: Lexer, msg: string) = 
  let coord = lexer.stream.getCoord(lexer.getPos)
  raise newException(KdlLexerError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{lexer.stream.errorAt(coord).indent(2)}\n")

proc dec(lexer: var Lexer, amount = 1) = 
  dec lexer.stream, amount

proc inc(lexer: var Lexer, amount = 1) = 
  inc lexer.stream, amount

proc literal(lexer: var Lexer, lit: string, consume = true): bool {.discardable.} = 
  result = lexer.peek(lit)
  if result and consume:
    lexer.inc lit.len

proc skipWhile(lexer: var Lexer, x: set[char]): int {.discardable.} = 
  while not lexer.eof() and lexer.peek() in x:
    inc result
    inc lexer

proc tokenNumWhole() {.lexing: tkEmpty.} = 
  if lexer.peek() in {'-', '+'}:
    inc lexer

  if lexer.peek() notin Digits:
    lexer.setPos before
    return

  inc lexer

  lexer.skipWhile(Digits + {'_'})

proc tokenNumExp(lexer: var Lexer) = 
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
    if lexer.peek() notin {'0'..'7'}:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile({'0'..'7', '_'})

proc tokenStringBody(lexer: var Lexer, raw = false) = 
  let before = lexer.getPos()

  if raw:
    if lexer.peek() != 'r': return

    inc lexer

  let hashes = lexer.skipWhile({'#'})

  if lexer.peek() != '"':
    lexer.setPos before
    return

  inc lexer

  var terminated = false

  while not lexer.eof():
    case lexer.peek()
    of '\\':
      if raw:
        inc lexer
        continue

      let next = lexer.peek(1)
      if next notin escapeTable:
        lexer.error &"Invalid escape '{next}'"

      lexer.inc 2

      if next == 'u':
        if lexer.peek() != '{':
          lexer.error "Expected opening bracket '{'"

        inc lexer

        let digits = lexer.skipWhile(HexDigits)
        if digits notin 1..6:
          lexer.error &"Expected 1-6 hexadecimal digits but found {digits}"

        if lexer.peek() != '}':
          lexer.error "Expected closing bracket '}'"

    of '"':
      inc lexer
      let endHashes = lexer.skipWhile({'#'})
      if not raw or hashes == 0 or endHashes == hashes:
        terminated = true
        break
      elif endHashes > hashes:
        lexer.error &"Expected {hashes} hashes but found {endHashes}"
    else:
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
  if not lexer.eof() and (let rune = lexer.stream.peekRune(); rune.int in whitespaces):
    lexer.inc rune.size
  else:
    lexer.tokenMultiLineComment()

proc skipWhitespaces*() {.lexing: tkEmpty.} = 
  while lexer.tokenWhitespace():
    discard

proc tokenNewLine*() {.lexing: tkNewLine.} = 
  for nl in newLines:
    if lexer.peek(nl):
      lexer.inc nl.len
      break

proc tokenIdent*() {.lexing: tkIdent.} = 
  if lexer.eof() or lexer.peek() in nonInitialChars:
    return

  # echo lexer.getPos(), " ", lexer.literal("null")
  # Check the identifier is similar to a boolean, null or number, and if it is it should follow the EOF, a whitespace, a new line or any non-ident char in order to be discarded.
  if (
      lexer.literal("true") or lexer.literal("false") or lexer.literal("null") or 
      lexer.tokenNumHex(addToStack = false) or lexer.tokenNumBin(addToStack = false) or lexer.tokenNumOct(addToStack = false) or lexer.tokenNumFloat(addToStack = false) or lexer.tokenNumInt(addToStack = false)
    ):
    if (lexer.eof() or lexer.tokenWhitespace(addToStack = false) or lexer.tokenNewLine(addToStack = false) or lexer.peek() in nonIdenChars):
      lexer.setPos before
      return

  block outer:
    while not lexer.eof() or not lexer.tokenWhitespace(consume = false) or not lexer.tokenNewLine(consume = false):
      let rune = lexer.stream.peekRune()
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
  if not lexer.tokenSingleLineComment(addToStack = false) and not lexer.tokenNewLine(addToStack = false):
      lexer.error "Expected a new line"

proc tokenLitMatches() {.lexing: tkEmpty.} = 
  ## Tries to match any of the litMatches literals.
  for (lit, kind) in litMatches:
    if lexer.literal(lit):
      lexer.add(kind, before)
      break

proc validToken*(source: sink string, token: proc(lexer: var Lexer, consume = true, addToStack = true): bool): bool = 
  var lexer = Lexer(stream: newStringStream(source))

  try:
    result = lexer.token() and lexer.eof()
  except KdlLexerError:
    return

proc scanKdl*(lexer: var Lexer) = 
  const choices = [
    tokenWhitespace, 
    tokenNewLine, 
    tokenLineCont, 
    tokenSingleLineComment, 
    tokenRawString, 
    tokenString, 
    tokenIdent, 
    tokenNumHex, 
    tokenNumBin, 
    tokenNumOct, 
    tokenNumFloat, 
    tokenNumInt, 
    tokenLitMatches, 
  ]

  while not lexer.eof():
    var anyMatch = false

    for choice in choices:
      if lexer.choice():
        anyMatch = true
        break

    if not anyMatch:
      lexer.error "Could not match any pattern"

proc scanKdl*(stream: Stream): Lexer = 
  result = Lexer(stream: stream)
  result.scanKdl()

proc scanKdl*(source: sink string): Lexer = 
  scanKdl(newStringStream(source))

proc scanKdlFile*(path: string): Lexer = 
  scanKdl(openFileStream(path))
