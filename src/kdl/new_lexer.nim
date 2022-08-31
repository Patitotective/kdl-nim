import std/[parseutils, strformat, strutils, unicode, tables, macros]

type
  KDLError = object of ValueError
  KDLLexerError = object of KDLError

  TokenKind* = enum
    tkNull, 
    tkBool, 
    tkEqual, 
    tkEmpty, 
    tkIdent, 
    tkLineCont, 
    tkTypeAnnot, 
    tkString, tkRawString, 
    tkWhitespace, tkNewLine
    tkOpenBlock, tkCloseBlock, # Children block
    tkNumDec, tkNumHex, tkNumBin, tkNumOct, 

  Coord = tuple[line: int, col: int]

  Token* = object
    lexeme*: string
    coord*: Coord
    kind*: TokenKind

  Lexer* = object
    source*: string
    stack*: seq[Token]
    current*: int

const
  nonIdenChars = {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'}
  nonInitialChars = Digits + nonIdenChars
  whiteSpaces = {0x0009, 0x0020, 0x00A0, 0x1680, 0x2000..0x200A, 0x202F, 0x205F, 0x3000}
  newLines = ["\u000D\u000A", "\u000D", "\u000A", "\u0085", "\u000C", "\u2028", "\u2029"]
  escapeTable = {
    'n': "\u000A", # Line Feed
    'r': "\u000D", # Carriage Return
    't': "\u0009", # Character Tabulation (Tab)
    '\\': "\u005C", # Reverse Solidus (Backslash)
    '"': "\u0022", # Quotation Mark (Double Quote)
    'b': "\u0008", # Backspace
    'f': "\u000C", # Form Feed
    'u': "", # Unicode
  }.toTable

  litMatches = {
    "=": tkEqual, 
    "null": tkNull, 
    "true": tkBool, 
    "false": tkBool, 
    "\\": tkLineCont, 
    "{": tkOpenBlock, 
    "}": tkCloseBlock, 
  }

proc `$`(lexer: Lexer): string = 
  result = &"{(if lexer.current == lexer.source.len: \"SUCCESS\" else: \"FAIL\")} {lexer.current}/{lexer.source.len}\n\t"
  for token in lexer.stack:
    result.add(&"{token.lexeme}({token.kind}) ")

macro lexing(token: TokenKind, body: untyped) = 
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() = 
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(): bool {.discardable.} = 
  ## let before = lexer.current
  ## echo "hi"
  ## result = before != lexer.current
  ## ```

  body.expectKind(nnkProcDef)

  body.params[0] = ident"bool" # Return type
  body.addPragma(ident"discardable")

  # Modify the procedure statements list (body)
  let before = genSym(nskLet, "before")

  body[^1].insert(0, newNimNode(nnkLetSection).add(newNimNode(nnkIdentDefs).add(before).add(newEmptyNode()).add(newDotExpr(ident"lexer", ident"current"))))
  body[^1].add(newAssignment(ident"result", infix(before, "!=", newDotExpr(ident"lexer", ident"current"))))

  if token != bindSym"tkEmpty":
    body[^1].add(newIfStmt(
      (ident"result", newStmtList(
        newCall(newDotExpr(ident"lexer", ident"add"), token, before)
      ))
    ))

  result = body

proc getCoord(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.len, lines[^1].len+1)

proc add(lexer: var Lexer, kind: TokenKind, start: int, until = lexer.current) = 
  lexer.stack.add(Token(kind: kind, lexeme: lexer.source[start..<until], coord: lexer.source.getCoord(start)))

proc eof(lexer: Lexer, extra = 0): bool = 
  lexer.current + extra >= lexer.source.len

proc peek(lexer: var Lexer, next = 1): char = 
  if not lexer.eof(next):
    result = lexer.source[lexer.current + next]

proc until(lexer: var Lexer, until: int): string = 
  if not lexer.eof(until):
    result = lexer.source[lexer.current..<lexer.current +  until]

proc error(lexer: Lexer, msg: string) = 
  let coord = lexer.source.getCoord(lexer.current)
  raise newException(KDLLexerError, &"{msg} at {coord.line}:{coord.col}")

proc consume(lexer: var Lexer, amount = 1) = 
  lexer.current += amount

proc literal(lexer: var Lexer, lit: string): bool {.discardable.} = 
  if lexer.source.continuesWith(lit, lexer.current):
    lexer.consume lit.len
    result = true

proc skipWhile(lexer: var Lexer, x: set[char]): int = 
  lexer.source.skipWhile(x, lexer.current)

proc tokenIdent(lexer: var Lexer) {.lexing(tkIdent).} = 
  if lexer.eof():
    return
  elif lexer.peek() in nonInitialChars or (lexer.peek() == '-' and lexer.peek(2) in Digits):
    lexer.error &"An identifier cannot start with {nonInitialChars} nor start with a hyphen ('-') and follow a digit"
  
  for rune in lexer.source[lexer.current..^1].runes: # FIXME: slicing copies string, unnecessary, better copy unicode and replace string with openArray[char]
    if rune.int <= 0x20:
      # lexer.error &"Identifiers cannot have lower codepoints than 32, found {rune.int}"
      break

    for c in nonIdenChars + {' '}:
      if rune == Rune(c):
        break

    lexer.consume rune.size

proc tokenNumExp*(lexer: var Lexer) = 
  if lexer.peek().toLowerAscii() == 'e':
    return

  lexer.consume()

  if lexer.peek() in {'-', '+'}:
    lexer.consume()  

  if (let digits = lexer.skipWhile(Digits + {'_'}); digits > 0):
    lexer.consume digits
  else: return

proc tokenNumFloat*(lexer: var Lexer) = 
  if lexer.peek() != '.':
    return

  lexer.consume()

  if (let digits = lexer.skipWhile(Digits + {'_'}); digits > 0):
    lexer.consume digits
  else: return

  if lexer.peek().toLowerAscii() == 'e':
    lexer.tokenNumExp()

proc tokenNumDec*(lexer: var Lexer) {.lexing(tkNumDec).} = 
  if lexer.peek() in {'-', '+'}:
    lexer.consume()

  let digits = lexer.source.skipWhile(Digits + {'_'}, lexer.current)

  if digits <= 0:
    return

  lexer.consume digits

  case lexer.peek()
  of 'e':
    lexer.tokenNumExp()
  of '.':
    lexer.tokenNumFloat()
  else: discard

proc tokenNumBin(lexer: var Lexer) {.lexing(tkNumBin).} = 
  if lexer.until(2) == "0b":
    lexer.consume lexer.skipWhile({'0', '1', '_'})

proc tokenNumHex(lexer: var Lexer) {.lexing(tkNumHex).} = 
  if lexer.until(2) == "0x":
    lexer.consume lexer.skipWhile(HexDigits + {'_'})

proc tokenNumOct(lexer: var Lexer) {.lexing(tkNumOct).} = 
  if lexer.until(2) == "0o":
    lexer.consume lexer.skipWhile({'0'..'7', '_'})

proc tokenStringBody(lexer: var Lexer, raw = false) = 
  if lexer.peek() != '"':
    if raw:
      lexer.error "Double quote expected"
    else:
      return

  lexer.consume()

  while not lexer.eof():
    case lexer.peek()
    of '\\':
      if raw:
        lexer.consume()
        continue

      let next = lexer.peek(2)
      if next notin escapeTable:
        return

      lexer.consume()

      if next == 'u':
        if lexer.peek(2) != '{':
          lexer.error "Expected opening bracket '{'"

        lexer.consume 2

        let digits = lexer.skipWhile(HexDigits)
        if digits notin 1..6:
          lexer.error &"Expected 1-6 hexadecimal digits but found {digits}"

        if lexer.peek() != '}':
          lexer.error "Expected closing bracket '}'"

    of '"':
      lexer.consume()
      break
    else:
      lexer.consume()

proc tokenRawString*(lexer: var Lexer) {.lexing(tkRawString).} =
  if lexer.peek() != 'r':
    return

  lexer.consume()

  var hashes = 0 # Number of hashes after raw string

  hashes = lexer.skipWhile({'#'})
  lexer.consume hashes

  lexer.tokenStringBody()

  if (let endHashes = lexer.skipWhile({'#'}); endHashes != hashes):
    lexer.error &"Expected {hashes} hashes ('#') but found {endHashes}"

  lexer.consume hashes

proc tokenString*(lexer: var Lexer) {.lexing(tkString).} =
  lexer.tokenStringBody()

proc tokenTypeAnnot*(lexer: var Lexer) {.lexing(tkTypeAnnot).} = 
  if lexer.peek() != '(':
    return

  lexer.consume()

  lexer.tokenIdent()

  if lexer.peek() != ')':
    lexer.error "Expected closing parenthesis ')'"

  lexer.consume()

proc tokenWhitespace*(lexer: var Lexer) {.lexing(tkWhitespace).} = 
  if not lexer.eof() and (let rune = lexer.source.runeAt(lexer.current); rune.int in whitespaces):
    lexer.consume rune.size

proc skipWhitespaces*(lexer: var Lexer) {.lexing(tkEmpty).} = 
  while lexer.tokenWhitespace():
    discard

proc tokenNewLine*(lexer: var Lexer) {.lexing(tkNewLine).} = 
  for nl in newLines:
    if lexer.until(nl.len) == nl:
      lexer.consume nl.len
      break

proc tokenSingleLineComment*(lexer: var Lexer) {.lexing(tkEmpty).} = 
  if lexer.until(2) != "//":
    return

  lexer.consume 2

  while not lexer.eof():
    if lexer.tokenNewLine(): break

proc tokenLitMatches*(lexer: var Lexer): bool {.discardable.} = 
  ## Tries to match any of the litMatches literals.
  let before = lexer.current

  for (lit, kind) in litMatches:
    if lexer.literal(lit):
      lexer.add(kind, before) # Before is implicitly created by the lexing macro
      break

  result = before != lexer.current

proc scan*(lexer: var Lexer) = 
  const choices = [tokenIdent, tokenTypeAnnot, tokenRawString, tokenString, tokenNumDec, tokenNumHex, tokenNumBin, tokenNumOct, tokenWhitespace, tokenNewLine, tokenSingleLineComment, tokenLitMatches]

  while not lexer.eof():
    for choice in choices:
      let prevLexer = lexer
      if lexer.choice():
        continue
      else:
        lexer = prevLexer

proc scan*(source: string, start = 0): Lexer = 
  result = Lexer(source: source, current: start)
  result.scan()

echo scan("title \"Hello, World\"").stack
