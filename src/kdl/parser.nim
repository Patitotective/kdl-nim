import npeg

const parser* = peg("nodes"):
  nodes <- *linespace * ?(node * ?nodes) * *linespace

  node <- slashDashComment * ?typeAnnotation * identifier * *(+nodeSpace * nodePropOrArg) * ?(*nodeSpace * nodeChildren * *ws) * *nodeSpace * nodeTerminator
  nodePropOrArg <- slashDashComment * (prop | value)
  nodeChildren <- slashDashComment * '{' * nodes * '}'
  nodeSpace <- *ws * escline * *ws | +ws
  nodeTerminator <- singleLineComment | newline | ';' | eof

  identifier <- str | bareIdentifier
  bareIdentifier <- (startIdentifierChar * *identifierChar | sign * ?((identifierChar - Digit) * *identifierChar)) - (keyword * !identifierChar)
  startIdentifierChar <- identifierChar - (Digit | sign)
  identifierChar <- 1 - (linespace | {'\\', '/', '(', ')', '{', '}', '<', '>', ';', '[', ']', '=', ',', '"'})
  keyword <- boolean | "null"
  prop <- identifier * '=' * value
  value <- ?typeAnnotation * (str | number | keyword)
  typeAnnotation <- '(' * identifier * ')'

  str <- rawString | escapedString
  escapedString <- '"' * *character * '"'
  character <- '\\' * escape | (1 - {'\\', '"'})
  escape <- {'"', '\\', '/', 'b', 'f', 'n', 'r', 't'} | i"u" * '{' * Xdigit[1..6] * '}'

  rawString <- 'r' * rawStringHash
  rawStringHash <- R("hashes", *'#') * rawStringQuotes * R("hashes")
  rawStringQuotes <- '"' * *(!('"' * R("hashes")) * 1) * '"'

  number <- hex | octal | binary | decimal

  decimal <- ?sign * integer * ?('.' * integer) * ?exponent
  exponent <- i"e" * ?sign * integer
  integer <- Digit * *(Digit | '_')
  sign <- {'+', '-'}

  hex <- ?sign * "0x" * Xdigit * *(Xdigit | '_')
  octal <- ?sign * "0o" * {'0'..'7'} * *{'0'..'7', '_'}
  binary <- ?sign * "0b" * {'0', '1'} * *{'0', '1', '_'}

  boolean <- "true" | "false"

  escline <- '\\' * *ws * (singleLineComment | newline)

  linespace <- newline | ws | singleLineComment

  newline <- "\c" | "\l" | "\c\l" | "\u000C" | "\f" | "\u2028" | "\u2029"

  ws <- bom | unicodeSpace | multiLineComment

  bom <- "\uFEFF"

  unicodeSpace <- "\u0009" | "\u0020" | "\u00A0" | "\u1680" | "\u2000" | "\u200A" | "\u202F" | "\u205F" | "\u3000"

  eof <- !1

  slashDashComment <- ?("/-" * *nodeSpace)
  singleLineComment <- "//" * +(1 - newline) * (newline | eof)
  multiLineComment <- "/*" * commentedBlock
  commentedBlock <- "*/" | (multiLineComment | '*' | '/' | +(1 - {'*', '/'})) * commentedBlock

proc validKDL*(input: string): bool = 
  let res = parser.match(input)
  res.ok and res.matchLen == res.matchMax
