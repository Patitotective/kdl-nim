type
  KdlError* = object of ValueError
  KdlLexerError* = object of KdlError
  KdlParserError* = object of KdlError

proc quoted*(x: string): string = result.addQuoted(x)
