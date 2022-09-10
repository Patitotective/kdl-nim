import std/[strformat, strutils, unicode, tables, macros]

type
  KdlError* = object of ValueError
  KdlLexerError* = object of KdlError

  TokenKind* = enum
    tkEmpty = "empty", 
    tkNull = "null", 
    tkBool = "bool", 
    tkEqual = "equal", 
    tkIdent = "identifier", 
    tkSemicolon = "semicolon", 
    tkSlashDash = "slash_dash", 
    tkString = "string", tkRawString = "raw_string", 
    tkWhitespace = "whitespace", tkNewLine = "new_line", 
    tkOpenType = "open_parenthesis", tkCloseType = "close_parenthesis", # Type annotation
    tkOpenBlock = "open_bracket", tkCloseBlock = "close_bracket", # Children block
    tkNumDec = "decimal_number", tkNumHex = "hexadecimal_number", tkNumBin = "binary_number", tkNumOct = "octagonal_number", 

  Coord* = tuple[line: int, col: int]

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
  whitespaces = {0x0009, 0x0020, 0x00A0, 0x1680, 0x2000..0x200A, 0x202F, 0x205F, 0x3000}
  newLines = ["\c\l", "\r", "\n", "\u0085", "\f", "\u2028", "\u2029"]
  escapeTable* = {
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
    ";": tkSemicolon, 
    "/-": tkSlashDash,  
    "{": tkOpenBlock, "}": tkCloseBlock,
    "(": tkOpenType, ")": tkCloseType,
  }


proc getCoord(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.high, lines[^1].len)

proc errorAt*(source: string, coord: tuple[line, col: int]): string = 
  let lines = source.splitLines
  if coord.line > lines.len:
    return &"Invalid line {coord.line}, expected one in 0..{lines.high}"

  let line = lines[coord.line]

  let lineNum = &"{coord.line + 1} | "
  result.add(&"{lineNum}{line}\n")
  result.add(&"{repeat(' ', lineNum.len + coord.col)}^\n")

proc `$`*(lexer: Lexer): string = 
  result = &"{(if lexer.current == lexer.source.len: \"SUCCESS\" else: \"FAIL\")} {lexer.current}/{lexer.source.len}\n\t"
  for token in lexer.stack:
    result.addQuoted(token.lexeme)
    result.add(&"({token.kind}) ")

macro lexing(token: TokenKind, body: untyped) = 
  ## Converts a procedure definition like:
  ## ```nim
  ## proc foo() = 
  ##   echo "hi"
  ## ```
  ## Into
  ## ```nim
  ## proc foo(consume: bool = true, addToStack: bool = true): bool {.discardable.} = 
  ## let before = lexer.current
  ## echo "hi"
  ## result = before != lexer.current
  ## if not consume:
  ##   lexer.current = before
  ## ```

  body.expectKind(nnkProcDef)

  body.params[0] = ident"bool" # Return type
  body.params.add(newIdentDefs(ident"consume", ident"bool", newLit(true)))
  body.params.add(newIdentDefs(ident"addToStack", ident"bool", newLit(true)))

  body.addPragma(ident"discardable")

  # Modify the procedure statements list (body)
  let before = genSym(nskLet, "before")

  body[^1].insert(0, newNimNode(nnkLetSection).add(newNimNode(nnkIdentDefs).add(before).add(newEmptyNode()).add(newDotExpr(ident"lexer", ident"current"))))
  body[^1].add(newAssignment(ident"result", infix(before, "!=", newDotExpr(ident"lexer", ident"current"))))
  body[^1].add(newIfStmt(
    (prefix(ident"consume", "not"), newStmtList(
      newAssignment(newDotExpr(ident"lexer", ident"current"), before)
    ))
  ))
  if token != bindSym"tkEmpty":
    body[^1].add(newIfStmt(
      (infix(ident"result", "and", ident"addToStack"), newStmtList(
        newCall(newDotExpr(ident"lexer", ident"add"), token, before)
      ))
    ))

  result = body

proc add(lexer: var Lexer, kind: TokenKind, start: int, until = lexer.current) = 
  lexer.stack.add(Token(kind: kind, lexeme: lexer.source[start..<until], coord: lexer.source.getCoord(start)))

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

proc literal(lexer: var Lexer, lit: string): bool {.discardable.} = 
  if lexer.source.continuesWith(lit, lexer.current):
    lexer.consume lit.len
    result = true

proc skipWhile(lexer: var Lexer, x: set[char]): int {.discardable.} = 
  while not lexer.eof() and lexer.peek() in x:
    inc result
    lexer.consume()

proc tokenNumExp(lexer: var Lexer) = 
  if lexer.peek().toLowerAscii() != 'e':
    return

  lexer.consume()

  if lexer.peek() in {'-', '+'}:
    lexer.consume()  

  if lexer.peek() notin Digits:
    lexer.error "Expected one or more digits"

  lexer.skipWhile(Digits + {'_'})

proc tokenNumFloat(lexer: var Lexer) = 
  if lexer.peek() != '.':
    return

  lexer.consume()

  if lexer.peek() notin Digits:
    lexer.error "Expected one or more digits"

  lexer.skipWhile(Digits + {'_'})

  if lexer.peek().toLowerAscii() == 'e':
    lexer.tokenNumExp()

proc tokenNumDec(lexer: var Lexer) {.lexing(tkNumDec).} = 
  if lexer.peek() in {'-', '+'}:
    lexer.consume()

  if lexer.peek() notin Digits:
    return

  lexer.consume()

  lexer.skipWhile(Digits + {'_'})

  case lexer.peek()
  of 'e':
    lexer.tokenNumExp()
  of '.':
    lexer.tokenNumFloat()
  else: discard

proc tokenNumBin(lexer: var Lexer) {.lexing(tkNumBin).} = 
  if lexer.until(2) == "0b":
    lexer.consume 2
    if lexer.peek() notin {'0', '1'}:
      lexer.error "Expected one or more binary digits"

    lexer.skipWhile({'0', '1', '_'})

proc tokenNumHex(lexer: var Lexer) {.lexing(tkNumHex).} = 
  if lexer.until(2) == "0x":
    lexer.consume 2
    if lexer.peek() notin HexDigits:
      lexer.error "Expected one or more octal digits"

    lexer.skipWhile(HexDigits + {'_'})

proc tokenNumOct(lexer: var Lexer) {.lexing(tkNumOct).} = 
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

    else:
      lexer.consume()

  if not terminated:
    lexer.error "Unterminated string"

proc tokenString(lexer: var Lexer) {.lexing(tkString).} =
  lexer.tokenStringBody()

proc tokenRawString(lexer: var Lexer) {.lexing(tkRawString).} =
  lexer.tokenStringBody(raw = true)

proc tokenWhitespace(lexer: var Lexer) {.lexing(tkWhitespace).} = 
  if not lexer.eof() and (let rune = lexer.source.runeAt(lexer.current); rune.int in whitespaces):
    lexer.consume rune.size

proc skipWhitespaces(lexer: var Lexer) {.lexing(tkEmpty).} = 
  while lexer.tokenWhitespace():
    discard

proc tokenNewLine(lexer: var Lexer) {.lexing(tkNewLine).} = 
  for nl in newLines:
    # if lexer.current > 0:
      # echo nl.escape(), " == ", lexer.until(nl.len).escape(), " ", nl == lexer.until(nl.len), " ", escape $lexer.peek()
    if lexer.until(nl.len) == nl:
      lexer.consume nl.len
      break

proc tokenIdent(lexer: var Lexer) {.lexing(tkIdent).} = 
  if lexer.eof() or lexer.peek() in nonInitialChars or (lexer.peek() == '-' and lexer.peek(2) in Digits):
    # lexer.error &"An identifier cannot start with {nonInitialChars} nor start with a hyphen ('-') and follow a digit"
    return
  
  block outer:
    for rune in lexer.source[lexer.current..^1].runes: # FIXME: slicing copies string, unnecessary, better copy unicode and replace string with openArray[char]
      if rune.int <= 0x20 or lexer.eof() or lexer.tokenWhitespace(consume = false) or lexer.tokenNewLine(consume = false):
        # lexer.error &"Identifiers cannot have lower codepoints than 32, found {rune.int}"
        break outer

      for c in nonIdenChars:
        if rune == Rune(c):
          break outer

      lexer.consume rune.size

proc tokenSingleLineComment(lexer: var Lexer) {.lexing(tkEmpty).} = 
  if lexer.until(2) != "//":
    return

  lexer.consume 2

  while not lexer.eof():
    if lexer.tokenNewLine(addToStack = false):
      break
    lexer.consume()

proc tokenMultiLineComment(lexer: var Lexer) {.lexing(tkEmpty).} = 
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

proc tokenLineCont(lexer: var Lexer) {.lexing(tkEmpty).} = 
  if lexer.peek() != '\\':
    return

  lexer.consume()

  lexer.skipwhitespaces()
  if not lexer.tokenSingleLineComment() and not lexer.tokenNewLine(addToStack = false):
      lexer.error "Expected a new line"

proc tokenLitMatches(lexer: var Lexer) {.lexing(tkEmpty).} = 
  ## Tries to match any of the litMatches literals.
  let before = lexer.current

  for (lit, kind) in litMatches:
    if lexer.literal(lit):
      lexer.add(kind, before)
      break

  result = before != lexer.current

proc scanKdl*(lexer: var Lexer) = 
  const choices = [
    tokenWhitespace, 
    tokenNewLine, 
    tokenLineCont, 
    tokenSingleLineComment, 
    tokenMultiLineComment, 
    tokenRawString, 
    tokenString, 
    tokenNumHex, 
    tokenNumBin, 
    tokenNumOct, 
    tokenNumDec, 
    tokenLitMatches, 
    tokenIdent, 
  ]

  while not lexer.eof():
    var anyMatch = false

    for choice in choices:
      let prevLexer = lexer

      if lexer.choice():
        anyMatch = true
        break
      else:
        ## FIXME: echo "Backtracking: ", lexer != prevLexer
        lexer = prevLexer

    if not anyMatch:
      lexer.error "Could not match any pattern"

proc scanKdl*(source: string, start = 0): Lexer = 
  result = Lexer(source: source, current: start)
  result.scanKdl()

proc scanKdlFile*(path: string): Lexer = 
  scanKdl(readFile(path))

# echo scanKdl("rata")
