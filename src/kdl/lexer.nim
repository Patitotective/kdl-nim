import std/[strformat, strutils, unicode, tables, macros]
import utils

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
    source*: string
    stack*: seq[Token]
    current*: int

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
  result = &"{(if lexer.current == lexer.source.len: \"SUCCESS\" else: \"FAIL\")} {lexer.current}/{lexer.source.len}\n\t"
  for token in lexer.stack:
    result.addQuoted(token.lexeme)
    result.add(&"({token.kind}) ")

macro lexing(token: TokenKind, body: untyped) = 
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() {.lexing: tkEmpty.} = 
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(lexer: var Lexer, consume: bool = true, addToStack: bool = true): bool {.discardable.} = 
  ##   let before = lexer.current
  ##   echo "hi"
  ##   result = before != lexer.current
  ##   if not consume:
  ##     lexer.current = before
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
  let before = genSym(nskLet, "before")

  body[^1].insert(0, quote do:
    let `before` = lexer.current
  )
  body[^1].add(quote do:
    result = `before` != lexer.current
  )
  body[^1].add(quote do:
    if not consume:
      lexer.current = `before`
  )

  if token != bindSym"tkEmpty":
    body[^1].add(quote do:
      if result and addToStack:
        lexer.add(`token`, `before`)
    )

  result = body

proc add(lexer: var Lexer, kind: TokenKind, start: int, until = lexer.current) = 
  lexer.stack.add(Token(kind: kind, lexeme: lexer.source[start..<until], start: start))

proc eof(lexer: Lexer, extra = 0): bool = 
  lexer.current + extra >= lexer.source.len

proc peek(lexer: var Lexer, next = 0): char = 
  if not lexer.eof(next):
    result = lexer.source[lexer.current + next]

proc until(lexer: var Lexer, until: int): string = 
  if not lexer.eof(until - 1):
    result = lexer.source[lexer.current..<lexer.current +  until]

proc error(lexer: Lexer, msg: string) = 
  let coord = lexer.source.getCoord(lexer.current)
  raise newException(KdlLexerError, &"{msg} at {coord.line + 1}:{coord.col + 1}\n{lexer.source.errorAt(coord).indent(2)}")

proc consume(lexer: var Lexer, amount = 1) = 
  lexer.current += amount

proc literal(lexer: var Lexer, lit: string, consume = true): bool {.discardable.} = 
  if lexer.source.continuesWith(lit, lexer.current):
    if consume:
      lexer.consume lit.len
    result = true

proc skipWhile(lexer: var Lexer, x: set[char]): int {.discardable.} = 
  while not lexer.eof() and lexer.peek() in x:
    inc result
    lexer.consume()

proc tokenNumWhole() {.lexing: tkEmpty.} = 
  let before = lexer.current
  if lexer.peek() in {'-', '+'}:
    lexer.consume()

  if lexer.peek() notin Digits:
    lexer.current = before
    return

  lexer.consume()

  lexer.skipWhile(Digits + {'_'})

proc tokenNumExp(lexer: var Lexer) = 
  if lexer.peek().toLowerAscii() != 'e':
    return

  lexer.consume()

  if lexer.peek() in {'-', '+'}:
    lexer.consume()  

  if lexer.peek() notin Digits:
    lexer.error "Expected one or more digits"

  lexer.skipWhile(Digits + {'_'})

proc tokenNumFloat() {.lexing: tkNumFloat.} = 
  let before = lexer.current
  if not lexer.tokenNumWhole():
    lexer.current = before
    return

  if lexer.peek() == '.':
    lexer.consume()

    if lexer.peek() notin Digits:
      lexer.error "Expected one or more digits"

    lexer.skipWhile(Digits + {'_'})

    if lexer.peek().toLowerAscii() == 'e':
      lexer.tokenNumExp()
 
  elif lexer.peek().toLowerAscii() == 'e':
    lexer.tokenNumExp()
  else:
    lexer.current = before
    return

proc tokenNumInt*() {.lexing: tkNumInt.} = 
  lexer.tokenNumWhole()

proc tokenNumBin*() {.lexing: tkNumBin.} = 
  if lexer.until(2) == "0b":
    lexer.consume 2
    if lexer.peek() notin {'0', '1'}:
      lexer.error "Expected one or more binary digits"

    lexer.skipWhile({'0', '1', '_'})

proc tokenNumHex*() {.lexing: tkNumHex.} = 
  if lexer.until(2) == "0x":
    lexer.consume 2
    if lexer.peek() notin HexDigits:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile(HexDigits + {'_'})

proc tokenNumOct*() {.lexing: tkNumOct.} = 
  if lexer.until(2) == "0o":
    lexer.consume 2
    if lexer.peek() notin {'0'..'7'}:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile({'0'..'7', '_'})

proc tokenStringBody(lexer: var Lexer, raw = false) = 
  let before = lexer.current

  if raw:
    if lexer.peek() != 'r': return

    lexer.consume()

  let hashes = lexer.skipWhile({'#'})

  if lexer.peek() != '"':
    lexer.current = before
    return

  lexer.consume()

  var terminated = false

  while not lexer.eof():
    case lexer.peek()
    of '\\':
      if raw:
        lexer.consume()
        continue

      let next = lexer.peek(1)
      if next notin escapeTable:
        lexer.error &"Invalid escape '{next}'"

      lexer.consume 2

      if next == 'u':
        if lexer.peek() != '{':
          lexer.error "Expected opening bracket '{'"

        lexer.consume()

        let digits = lexer.skipWhile(HexDigits)
        if digits notin 1..6:
          lexer.error &"Expected 1-6 hexadecimal digits but found {digits}"

        if lexer.peek() != '}':
          lexer.error "Expected closing bracket '}'"

    of '"':
      lexer.consume()
      let endHashes = lexer.skipWhile({'#'})
      if not raw or hashes == 0 or endHashes == hashes:
        terminated = true
        break
      elif endHashes > hashes:
        lexer.error &"Expected {hashes} hashes but found {endHashes}"
    elif lexer.literal("\r\n", consume = false): # Replace CRLF with LF
      lexer.source[lexer.current..lexer.current + 1] = "\n"
      lexer.consume()
    else:
      lexer.consume()

  if not terminated:
    lexer.error "Unterminated string"

proc tokenString*() {.lexing: tkString.} =
  lexer.tokenStringBody()

proc tokenRawString*() {.lexing: tkRawString.} =
  lexer.tokenStringBody(raw = true)

proc tokenMultiLineComment*() {.lexing: tkEmpty.} = 
  if lexer.until(2) != "/*":
    return

  lexer.consume 2

  var nested = 1

  while not lexer.eof() and nested > 0:
    if lexer.until(2) == "*/":
      dec nested
      lexer.consume 2
    elif lexer.until(2) == "/*":
      inc nested
      lexer.consume 2
    else:
      lexer.consume()

  if nested > 0:
    lexer.error "Expected end of multi-line comment"

proc tokenWhitespace*() {.lexing: tkWhitespace.} = 
  if not lexer.eof() and (let rune = lexer.source.runeAt(lexer.current); rune.int in whitespaces):
    lexer.consume rune.size
  else:
    lexer.tokenMultiLineComment()

proc skipWhitespaces*() {.lexing: tkEmpty.} = 
  while lexer.tokenWhitespace():
    discard

proc tokenNewLine*() {.lexing: tkNewLine.} = 
  for nl in newLines:
    # if lexer.current > 0:
      # echo nl.escape(), " == ", lexer.until(nl.len).escape(), " ", nl == lexer.until(nl.len), " ", escape $lexer.peek()
    if lexer.until(nl.len) == nl:
      lexer.consume nl.len
      break

proc tokenIdent*() {.lexing: tkIdent.} = 
  if lexer.eof() or lexer.peek() in nonInitialChars:
    return

  let before = lexer.current
  # Check the identifier is similar to a boolean, null or number, and if it is it should follow the EOF, a whitespace, a new line or any non-ident char in order to be discarded.
  if (
      lexer.literal("true") or lexer.literal("false") or lexer.literal("null") or 
      lexer.tokenNumHex(addToStack = false) or lexer.tokenNumBin(addToStack = false) or lexer.tokenNumOct(addToStack = false) or lexer.tokenNumFloat(addToStack = false) or lexer.tokenNumInt(addToStack = false)
    ):
    if (lexer.eof() or lexer.tokenWhitespace(addToStack = false) or lexer.tokenNewLine(addToStack = false) or lexer.peek() in nonIdenChars):
      lexer.current = before
      return

  block outer:
    for rune in lexer.source[lexer.current..^1].runes: # FIXME: slicing copies string, unnecessary, better copy unicode and replace string with openarray[char]
      if rune.int <= 0x20 or rune.int > 0x10FFFF or lexer.eof() or lexer.tokenWhitespace(consume = false) or lexer.tokenNewLine(consume = false):
        break outer

      for c in nonIdenChars:
        if rune == Rune(c):
          break outer

      lexer.consume rune.size

proc tokenSingleLineComment*() {.lexing: tkEmpty.} = 
  if lexer.until(2) != "//":
    return

  lexer.consume 2

  while not lexer.eof(): # Consume until a new line or EOF
    if lexer.tokenNewLine(addToStack = addToStack):
      break

    lexer.consume()

proc tokenLineCont*() {.lexing: tkLineCont.} = 
  if lexer.peek() != '\\':
    return

  lexer.consume()

  lexer.skipwhitespaces()
  if not lexer.tokenSingleLineComment(addToStack = false) and not lexer.tokenNewLine(addToStack = false):
      lexer.error "Expected a new line"

proc tokenLitMatches() {.lexing: tkEmpty.} = 
  ## Tries to match any of the litMatches literals.
  let before = lexer.current

  for (lit, kind) in litMatches:
    if lexer.literal(lit):
      lexer.add(kind, before)
      break

proc validToken*(input: string, token: proc(lexer: var Lexer, consume = true, addToStack = true): bool): bool = 
  var lexer = Lexer(source: input, current: 0)

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

proc scanKdl*(source: string, start = 0): Lexer = 
  result = Lexer(source: source, current: start)
  result.scanKdl()

proc scanKdlFile*(path: string): Lexer = 
  scanKdl(readFile(path))
