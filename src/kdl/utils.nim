import std/[strformat, strutils]

type
  KdlError* = object of ValueError
  KdlLexerError* = object of KdlError
  KdlParserError* = object of KdlError

  Coord* = tuple[line: int, col: int]

proc quoted*(x: string): string = result.addQuoted(x)
  
proc getCoord*(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result = (lines.high, lines[^1].len)

proc errorAt*(source: string, coord: tuple[line, col: int]): string = 
  let line = source.splitLines[coord.line]

  let lineNum = &"{coord.line + 1} | "
  result.add(&"{lineNum}{line}\n")
  result.add(&"{repeat(' ', lineNum.len + coord.col)}^\n")
