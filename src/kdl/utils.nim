import std/[strformat, strutils]

import types

type
  Coord* = object
    line*, col*: int

template error*(msg: string) = 
  raise newException(KdlError, msg)

template check*(cond: untyped, msg = "") = 
  if not cond:
    let txt = msg
    error astToStr(cond) & " failed" & (if txt.len > 0: ": " & txt else: "")

proc quoted*(x: string): string = result.addQuoted(x)
  
proc getCoord*(str: string, idx: int): Coord =
  let lines = str[0..<idx].splitLines(keepEol = true)

  result.line = lines.high
  result.col = lines[^1].len

proc errorAt*(source: string, coord: Coord): string = 
  let line = source.splitLines[coord.line]

  let lineNum = &"{coord.line + 1} | "
  result.add(&"{lineNum}{line}\n")
  result.add(&"{repeat(' ', lineNum.len + coord.col)}^\n")
