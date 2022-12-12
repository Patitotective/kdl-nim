import std/[tables, os]
import parser, types

proc initKPrefs*(path: string, default: KdlDoc, stream = false): KdlPrefs[KdlDoc] =
  ## Initialize a KdlPrefs object, loading the content from path if it exists or using the default content.
  ## - Use `stream` to parse the file as a `FileStream`.

  result = KdlPrefs[KdlDoc](path: path, default: default)
  result.content = 
    if path.fileExists:
      if stream:
        parseKdlFileStream(path)
      else:
        parseKdlFile(path)
    else:
      default

proc initKPrefs*[T](path: string, default: T, stream = false): KdlPrefs[T] =
  ## Initialize a KdlPrefs object, loading the content from path if it exists or using the default content.
  ## - Use `stream` to parse the file as a `FileStream`.

  result = KdlPrefs[T](path: path, default: default)

  if path.fileExists:
    if stream:
      parseKdlFileStream(path).decode(result.content)
    else:
      parseKdlFile(path).decode(result.content)
  else:
    result.content = default

proc save*(prefs: KdlPrefs[KdlDoc]) =
  prefs.path.splitPath.head.createDir()
  prefs.path.writeFile($prefs.content & '\n')

proc save*(prefs: KdlPrefs[auto]) =
  prefs.path.splitPath.head.createDir()
  prefs.path.writeFile(prefs.content.encode())

proc removeFile*(prefs: KdlPrefs[auto]) =
  ## Deletes the preferences file if it exists.
  if prefs.path.fileExists:
    prefs.path.removeFile

template `[]`*(prefs: KdlPrefs[auto], field): untyped = 
  prefs.content.field

template `[]=`*(prefs: KdlPrefs[auto], field, val): untyped = 
  prefs.content.field = val

template `{}`*(prefs: KdlPrefs[auto], field): untyped = 
  prefs.default.field
