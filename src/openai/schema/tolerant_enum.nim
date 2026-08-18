import std/strutils
import jsonx/parsejson

proc readTolerantEnum*[T: enum](dst: var T; p: var JsonParser) =
  if p.tok != tkString:
    raiseParseErr(p, "string for an enum")
  dst = parseEnum[T](p.a, default(T))
  discard getTok(p)
