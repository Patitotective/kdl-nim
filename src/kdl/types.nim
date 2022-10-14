type
  KdlError* = object of CatchableError
  KdlLexerError* = object of KdlError
  KdlParserError* = object of KdlError
