import std/[parseutils, strutils, unicode, tables]

type
  ParseReturn = tuple[ok: bool, until: int]

const
  nonIdenChars = {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'}
  nonInitialChars = Digits + nonIdenChars
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

proc peek(input: string, index: int): char = 
  if index < input.len:
    result = input[index]

proc validateIden*(input: string, start: int): int = 
  ## Returns the index until an invalid identifier character or an space was found.
  result = start

  if (let first = input.peek(start); first in nonInitialChars or (first == '-' and input.peek(start + 1) in Digits)):
    return
  
  for rune in input[start..input.high].runes:
    if rune.int <= 0x20:
      return

    for c in nonIdenChars + {' '}:
      if rune == Rune(c):
        return

    result += rune.size

proc validateString*(input: string, start: int): ParseReturn =
  var raw = false
  var hashes = 0 # Number of hashes after raw string

  result.until = start

  if input.peek(start) == 'r':
    raw = true
    inc result.until

    while result.until < input.len and input.peek(result.until) == '#':
      inc hashes
      inc result.until

  if input.peek(result.until) != '"':
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
        if input.peek(result.until + 1) != '{':
          return

        result.until += 2

        while result.until < input.len and input.peek(result.until) in HexDigits:
          inc result.until

        if input.peek(result.until) != '}':
          return

    of '"':
      inc result.until

      if raw:
        var endHashes = 0
        while result.until < input.len and input.peek(result.until) == '#':
          inc endHashes
          inc result.until

        if hashes != endHashes:
          return

      result.ok = true
      break
    else:
      inc result.until

proc validateExponent*(input: string, start: int): ParseReturn = 
  result.until = start

  if input.peek(start) != 'e':
    return

  inc result.until # Consume the e

  if input.peek(start) in {'-', '+'}:
    inc result.until  

  if (let digits = input.skipWhile(Digits + {'_'}, result.until); digits > 0):
    result.until += digits
  else:
    return

  result.ok = true

proc validateFloating*(input: string, start: int): ParseReturn = 
  result.until = start
  if input.peek(start) != '.':
    return

  inc result.until # Consume point

  if (let digits = input.skipWhile(Digits + {'_'}, result.until); digits > 0):
    result.until += digits
  else:
    return

  if input.peek(result.until) == 'e':
    result = input.validateExponent(result.until)
  else:
    result.ok = true

proc validateDecimal*(input: string, start: int): ParseReturn = 
  result.until = start + input.skipWhile(Digits + {'_'}, result.until)

  case input.peek(result.until)
  of 'e':
    result = input.validateExponent(result.until)
  of '.':
    result = input.validateFloating(result.until)
  else:
    result.ok = true

proc validateNumber*(input: string, start: int): ParseReturn = 
  result.until = start

  if input.peek(start) in {'-', '+'}:
    inc result.until

  if result.until + 2 >= input.len:
    return input.validateDecimal(result.until)
  else:
    case input[result.until..<result.until+2]
    of "0b":
      result.until += input.skipWhile({'0', '1', '_'}, result.until)
    of "0x":
      result.until += input.skipWhile(HexDigits + {'_'}, result.until)
    of "0o":
      result.until += input.skipWhile({'0'..'7', '_'}, result.until)
    else:
      return input.validateDecimal(result.until)

  result.ok = true

proc validateBoolean*(input: string, start: int): ParseReturn = 
  if input.continuesWith("true", start):
    result = (true, start + 4)
  elif input.continuesWith("false", start):
    result = (true, start + 5)

proc validateNull*(input: string, start: int): ParseReturn = 
  if input.continuesWith("null", start):
    result = (true, start + 4)

let input = "13482935.8e3"
let result = validateNumber(input, 0)

if result.ok:
  echo input[0..<result.until], " :]"
else:
  echo "Failed :/ ", result 
