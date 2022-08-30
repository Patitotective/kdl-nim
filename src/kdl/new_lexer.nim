import std/[strformat, strutils, unicode]

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

  Lexer* = object
    source*: string
    stack*: seq[Token]
    current*: int

proc getCoord(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.len, lines[^1].len+1)

proc peek(lexer: var Lexer, next = 1): char = 
  if lexer.current + next < lexer.source.len:
    result = lexer.source[lexer.current + next]

proc eof(lexer: Lexer, extra = 0): bool = 
  lexer.current + extra >= lexer.source.len

proc error(lexer: Lexer, msg: string): bool = 
  let coord = lexer.source.getCoord(lexer.current)
  raise newException(KDLLexerError, &"{msg} at {coord.line}:{coord.col}")

proc consume(lexer: var Lexer, amount: int) = 
  lexer.current += amount

proc literal(lexer: var Lexer, lit: string) = 
  if lexer.source.continuesWith(lit, lexer.current):
    lexer.consume lit.len

proc tokenIdent(lexer: var Lexer) = 
  if lexer.eof() or lexer.peek() in nonInitialChars or (lexer.peek() == '-' and lexer.peek(2) in Digits):
    return
  
  for rune in lexer.source[lexer.current..^1].runes:
    if rune.int <= 0x20:
      # lexer.error(&"Identifiers cannot have lower codepoints than 32, found {rune.int}")
      return

    for c in nonIdenChars + {' '}:
      if rune == Rune(c):
        return

    lexer.consume rune.size

