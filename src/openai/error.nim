## Forward-compatible parsing for OpenAI API error envelopes.

import std/options
export options
import jsonx
import jsonx/parsejson

type
  OpenAIError* = object
    message*: string
    `type`*: string
    param*: Option[string]
    code*: Option[string]

  OpenAIErrorResponse* = object
    error*: OpenAIError

proc readJson*(dst: var OpenAIErrorResponse; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  var foundError = false
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    case p.a
    of "error":
      foundError = true
      discard getTok(p)
      eat(p, tkColon)
      readJson(dst.error, p, unknownFields)
    else:
      discard getTok(p)
      eat(p, tkColon)
      if unknownFields == ufSkip:
        skipJson(p)
      else:
        raiseParseErr(p, "valid object field")
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)
  if not foundError:
    raiseParseErr(p, "error field")

proc errorParse*(body: string; dst: out OpenAIErrorResponse): bool =
  ## Parses a forward-compatible error envelope.
  try:
    dst = fromJson(body, OpenAIErrorResponse)
    result = true
  except CatchableError:
    dst = default(OpenAIErrorResponse)
    result = false

proc errorOf*(x: OpenAIErrorResponse): lent OpenAIError =
  ## Returns the parsed API error.
  result = x.error

proc raiseErrorAccessorError(message: string) {.noinline, noreturn.} =
  raise newException(ValueError, message)

proc hasCode*(x: OpenAIError): bool {.inline.} =
  ## Returns whether the API reported a machine-readable error code.
  x.code.isSome

proc codeOf*(x: OpenAIError): lent string {.inline.} =
  ## Returns the API error code, raising `ValueError` when absent.
  if x.code.isNone:
    raiseErrorAccessorError("error has no code")
  result = x.code.get

proc hasParam*(x: OpenAIError): bool {.inline.} =
  ## Returns whether the API implicated a request parameter.
  x.param.isSome

proc paramOf*(x: OpenAIError): lent string {.inline.} =
  ## Returns the implicated request parameter, raising `ValueError` when absent.
  if x.param.isNone:
    raiseErrorAccessorError("error has no param")
  result = x.param.get
