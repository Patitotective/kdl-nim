import std/[parseutils, strformat, strutils, unicode, tables]

type
  KDLError = object of ValueError
  KDLLexerError = object of KDLError

  TokenKind* = enum
    tkNull, 
    tkBool, 
    tkEqual, 
    tkIdent, 
    tkNumber, 
    tkString, 
    tkTypeAnnot, 
    tkOpenBlock, tkCloseBlock, # Children block

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

proc getCoord(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.len, lines[^1].len+1)

proc eof(lexer: Lexer, extra = 0): bool = 
  lexer.current + extra >= lexer.source.len

proc peek(lexer: var Lexer, next = 1): char = 
  if not lexer.eof(next):
    result = lexer.source[lexer.current + next]

proc until(lexer: var Lexer, until: int): string = 
  if not lexer.eof(until):
    result = lexer.source[lexer.current..<lexer.current +  until]

proc error(lexer: Lexer, msg: string): bool = 
  let coord = lexer.source.getCoord(lexer.current)
  raise newException(KDLLexerError, &"{msg} at {coord.line}:{coord.col}")

proc consume(lexer: var Lexer, amount = 1) = 
  lexer.current += amount

proc literal(lexer: var Lexer, lit: string) = 
  if lexer.source.continuesWith(lit, lexer.current):
    lexer.consume lit.len

proc skipWhile(lexer: var Lexer, x: set[char]): int = 
  lexer.source.skipWhile(x, lexer.current)

proc tokenIdent(lexer: var Lexer): bool = # TODO: macro pragma that returns a bool whether the inital lexer.current differs from the one at the end of the procedure.
  if lexer.eof():
    return
  elif lexer.peek() in nonInitialChars or (lexer.peek() == '-' and lexer.peek(2) in Digits):
    lexer.error(&"An identifier cannot start with {nonInitialChars} nor start with a hyphen ('-') and follow a digit")
  
  for rune in lexer.source[lexer.current..^1].runes: # FIXME: slicing copies string, unnecessary, better copy unicode and replace string with openArray[char]
    if rune.int <= 0x20:
      # lexer.error(&"Identifiers cannot have lower codepoints than 32, found {rune.int}")
      break

    for c in nonIdenChars + {' '}:
      if rune == Rune(c):
        break

    lexer.consume rune.size

proc tokenExponent*(lexer: var Lexer) = 
  if lexer.peek().toLowerAscii() == 'e':
    return

  lexer.consume()

  if lexer.peek() in {'-', '+'}:
    lexer.consume()  

  if (let digits = lexer.skipWhile(Digits + {'_'}); digits > 0):
    lexer.consume digits
  else: return

proc tokenFloating*(lexer: var Lexer) = 
  if lexer.peek() != '.':
    return

  lexer.consume()

  if (let digits = lexer.skipWhile(Digits + {'_'}); digits > 0):
    lexer.consume digits
  else: return

  if lexer.peek().toLowerAscii() == 'e':
    lexer.tokenExponent()

proc tokenDecimal*(lexer: var Lexer) = 
  let digits = lexer.source.skipWhile(Digits + {'_'}, lexer.current)

  if digits <= 0:
    return

  lexer.consume digits

  case lexer.peek()
  of 'e':
    lexer.tokenExponent()
  of '.':
    lexer.tokenFloating()
  else: discard

proc tokenNumber(lexer: var Lexer) = 
  if lexer.peek() in {'-', '+'}:
    lexer.consume()

  case lexer.until(2)
  of "0b":
    lexer.consume lexer.skipWhile({'0', '1', '_'})
  of "0x":
    lexer.consume lexer.skipWhile(HexDigits + {'_'})
  of "0o":
    lexer.consume lexer.skipWhile({'0'..'7', '_'})
  else:
    lexer.tokenDecimal()

proc tokenString*(lexer: var Lexer) =
  var raw = false
  var hashes = 0 # Number of hashes after raw string

  if lexer.peek() == 'r':
    raw = true
    lexer.consume()

    hashes = lexer.skipWhile({'#'})
    lexer.consume hashes

  if lexer.peek() != '"':
    if raw:
      lexer.error("Double quote expected")
    else:
      return

  lexer.consume()

  while not lexer.eof():
    case lexer.peek()
    of '\\':
      if raw:
        lexer.consume()
        continue

      let next = input.peek(2)
      if next notin escapeTable:
        return

      lexer.consume()

      if next == 'u':
        if input.peek(2) != '{':
          lexer.error("Expected opening bracket '{'")

        lexer.consume 2

        let digits = lexer.skipWhile(HexDigits)
        if digits notin 1..6:
          lexer.error(&"Expected 1-6 hexadecimal digits but found {digits}")

        if lexer.peek() != '}':
          lexer.error("Expected closing bracket '}'")

    of '"':
      lexer.consume()

      if raw:
        if (let endHashes = lexer.skipWhile({'#'}); endHashes != hashes):
          lexer.error(&"Expected {hashes} hashes ('#') but found {endHashes}")

        lexer.consume hashes

      return
    else:
      lexer.consume()

proc tokenTypeAnnot*(lexer: var Lexer) = 
  if lexer.peek() != '(':
    return

  lexer.consume()

  lexer.tokenIdent()

  if lexer.peek() != ')':
    lexer.error("Expected closing parenthesis ')'")

  lexer.consume()

proc tokenNewLine*(lexer: var Lexer) = 
  for nl in newLines:
    if lexer.until(nl.len) == nl:
      lexer.consume nl.len
      break

proc tokenSingleLineComment*(lexer: var Lexer) = 
  if lexer.until(2) != "//":
    return

  lexer.consume 2

  while not lexer.eof():
    let before = lexer.current

    lexer.tokenNewLine()

    if lexer.current != before:
      break

proc validateLineContinuation*(input: string, start: int): ParseResult = 
  result.until = start

  if not input.peek(start, '\\'):
    return

  inc result.until

  result.until = input.skipWhitespaces(result.until)

  if (let res = input.validateSingleLineComment(result.until); res.ok):
    result = res
  else:
    result = input.validateNewLine(result.until)

proc validateProperty*(input: string, start: int): ParseResult = 
  validate input.validateNodeName(start)

  if input.peek(result.until) != '=':
    result.ok = false
    return

  inc result.until

  result = input.validateValue(result.until)
