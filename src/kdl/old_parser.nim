import std/[parseutils, strutils, unicode, tables]

type
  ParseResult = tuple[ok: bool, until: int]

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

proc peek(input: string, x: Slice[int]): string = 
  if x.a > 0 and x.b < input.len:
    result = input[x]

proc peek(input: string, index: int): char = 
  if index < input.len:
    result = input[index]

proc peek(input: string, index: int, c: char): bool = 
  input.peek(index) == c

proc peek(input: string, index: int, str: string): bool = 
  if index + str.len <= input.len:
    result = input[index..<index+str.len] == str

template validate(pattern: typed) =
  result = pattern
  if not result.ok: return

template choice(patterns: varags[typed]) = 
  if (let res = p; p.ok):
    result = res

proc validateIdent*(input: string, start: int): ParseResult = 
  result.until = start

  if (let first = input.peek(start); first in nonInitialChars or (first == '-' and input.peek(start + 1) in Digits)) or start >= input.len:
    return
  
  block outer:
    for rune in input[start..input.high].runes:
      if rune.int <= 0x20:
        break outer

      for c in nonIdenChars + {' '}:
        if rune == Rune(c):
          break outer

      result.until += rune.size

  result.ok = true

proc validateString*(input: string, start: int): ParseResult =
  var raw = false
  var hashes = 0 # Number of hashes after raw string

  result.until = start

  if input.peek(start, 'r'):
    raw = true
    inc result.until

    while result.until < input.len and input.peek(result.until, '#'):
      inc hashes
      inc result.until

  if not input.peek(result.until, '"'):
    return

  inc result.until # Consume the quote

  while result.until < input.len:
    case input.peek(result.until)
    of '\\':
      if raw:
        inc result.until
        continue

      let next = input.peek(result.until + 1)
      if next notin escapeTable:
        return

      inc result.until

      if next == 'u':
        if not input.peek(result.until + 1, '{'):
          return

        result.until += 2

        while result.until < input.len and input.peek(result.until) in HexDigits:
          inc result.until

        if not input.peek(result.until, '}'):
          return

    of '"':
      inc result.until

      if raw:
        var endHashes = 0
        while result.until < input.len and input.peek(result.until, '#'):
          inc endHashes
          inc result.until

        if hashes != endHashes:
          return

      result.ok = true
      break
    else:
      inc result.until

proc validateExponent*(input: string, start: int): ParseResult = 
  result.until = start

  if not input.peek(start, 'e'):
    return

  inc result.until # Consume the e

  if input.peek(start) in {'-', '+'}:
    inc result.until  

  if (let digits = input.skipWhile(Digits + {'_'}, result.until); digits > 0):
    result.until += digits
  else:
    return

  result.ok = true

proc validateFloating*(input: string, start: int): ParseResult = 
  result.until = start
  if not input.peek(start, '.'):
    return

  inc result.until # Consume point

  if (let digits = input.skipWhile(Digits + {'_'}, result.until); digits > 0):
    result.until += digits
  else:
    return

  if input.peek(result.until, 'e'):
    result = input.validateExponent(result.until)
  else:
    result.ok = true

proc validateDecimal*(input: string, start: int): ParseResult = 
  result.until = start
  let digits = input.skipWhile(Digits + {'_'}, start)

  if digits <= 0:
    return

  result.until += digits

  case input.peek(result.until)
  of 'e':
    result = input.validateExponent(result.until)
  of '.':
    result = input.validateFloating(result.until)
  else:
    result.ok = true

proc validateNumber*(input: string, start: int): ParseResult = 
  result.until = start

  if input.peek(start) in {'-', '+'}:
    inc result.until

  case input.peek(result.until..<result.until+2)
  of "0b":
    result.until += input.skipWhile({'0', '1', '_'}, result.until)
  of "0x":
    result.until += input.skipWhile(HexDigits + {'_'}, result.until)
  of "0o":
    result.until += input.skipWhile({'0'..'7', '_'}, result.until)
  else:
    return input.validateDecimal(result.until)

  result.ok = true

proc validateBoolean*(input: string, start: int): ParseResult = 
  if input.continuesWith("true", start):
    result = (true, start + 4)
  elif input.continuesWith("false", start):
    result = (true, start + 5)

proc validateNull*(input: string, start: int): ParseResult = 
  if input.continuesWith("null", start):
    result = (true, start + 4)

proc validateTypeAnnotation*(input: string, start: int): ParseResult = 
  result.until = start
  if not input.peek(start, '('):
    return

  inc result.until

  validate input.validateIdent(result.until)

  if not input.peek(result.until, ')'):
    return

  inc result.until

  result.ok = true

proc validateValue*(input: string, start: int): ParseResult = 
  if input.peek(start, '('):
    validate input.validateTypeAnnotation(start)

  if (let res = input.validateNull(start); res.ok):
    result = res
  elif (let res = input.validateBoolean(start); res.ok):
    result = res
  elif (let res = input.validateNumber(start); res.ok):
    result = res
  else:
    result = input.validateString(start)

proc validateNodeName*(input: string, start: int): ParseResult = 
  ## Validates wheter input is an identifier or string.
  if input.peek(start, '('):
    validate input.validateTypeAnnotation(start)

  if (let res = input.validateString(result.until); res.ok):
    result = res
  else:
    result = input.validateIdent(result.until)

proc validateWhitespace*(input: string, start: int): ParseResult = 
  result.until = start

  if (let rune = input.runeAt(start); rune.int in whitespaces):
    result.ok = true
    result.until += rune.size

proc skipWhitespaces*(input: string, start: int): int = 
  ## Returns the index when a non-whitespace character was found since start.
  result = start

  while (let res = input.validateWhitespace(result); res.ok):
    result = res.until

proc validateNewLine*(input: string, start: int): ParseResult = 
  result.until = start

  for nl in newLines:
    if input.peek(start, nl):
      result.ok = true
      result.until += nl.len
      break

proc validateSingleLineComment*(input: string, start: int): ParseResult = 
  result.until = start

  if not input.peek(start, "//"):
    return

  result.until += 2

  while result.until < input.len and (let res = input.validateNewLine(result.until); not res.ok):
    inc result.until

  result.ok = true

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

proc validateNodeSpace*(input: string, start: int): ParseResult = 
  result.until = input.skipWhitespaces(start)

proc validateNode*(input: string, start: int): ParseResult = 
  validate input.validateNodeName(start)
  validate input.validateWhitespace(result.until)

  result.until = input.skipWhitespaces(result.until)

  while true:
    valid input.validateProperty(result.until)
    # if (let res = input.validateProperty(result.until); res.ok):
      # result = res
    else:
      validate input.validateValue(result.until)

    validate input.validateWhitespace(result.until)

const input = "//a\nasddd"
const start = 0
let result = input.validateSingleLineComment(start)

if result.ok:
  echo input[start..<result.until], " :]"
else:
  echo "Failed :/ ", result 
