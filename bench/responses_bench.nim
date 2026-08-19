## Standalone benchmark for the hottest Responses API path: decoding a realistic
## response body and extracting what a consumer needs (first text, first function
## call, usage tokens, parsing call arguments).
##
## Strategies:
##   jsonx typed    : package `fromJson(body, ResponseResult)` + the real
##                    `openai/responses` accessors (`firstText`, `firstCallArgs`,
##                    `inputTokens`, ...). The full package is imported so we
##                    time the exact path a consumer runs, not a hand-rolled copy.
##   std/json typed : `parseJson(body).to(MyFlatTypes)` into flat own types.
##                    It projects known fields; `to` drops unknown item fields.
##   std/json direct: `parseJson(body)` + direct tree access of needed fields only
##   std/json parse : tree construction alone (floor for any std/json strategy)
##
## Extra rows time the tool-calling inner step: parsing the first call's
## arguments JSON (jsonx `parseFirstCallArgs` vs std `parseJson(s).to(T)`).
##
## Build: nim c -d:release -r bench/responses_bench.nim
## (the package import pulls in relay's curl bindings, hence the -lcurl below;
##  it affects link time only, not the measured hot loop)

import std/[json, monotimes, options, strformat, times]

import jsonx
import openai/responses

import responses_fixture

{.passL: "-lcurl".}

const WarmupIters = 3000

# --- jsonx side: package decode + the real openai/responses accessors ---------
# (`firstText`, `firstCallArgs`, `inputTokens`, `cachedInputTokens`,
#  `reasoningTokens`, `totalTokens`, `parseFirstCallArgs` are used directly)

# --- std/json side A: flat own types decoded with the `to` macro -------------
# `type` discriminators are plain strings: tolerant and case-object free.
# Open payloads are `JsonNode`. Server-omittable fields must be `Option`;
# a missing plain field makes `to` raise KeyError.

type
  StdPart = object
    `type`: string
    text: string
    refusal: Option[string]
    annotations: JsonNode
    logprobs: JsonNode

  StdSummaryPart = object
    `type`: string
    text: string

  StdItem = object
    id: string
    status: string
    `type`: string
    role: Option[string]
    content: Option[seq[StdPart]]
    arguments: Option[string]
    summary: Option[seq[StdSummaryPart]]
    encrypted_content: Option[string]

  StdError = object
    code: string
    message: string

  StdIncomplete = object
    reason: string

  StdInputDetails = object
    cached_tokens: int
    cache_write_tokens: int

  StdOutputDetails = object
    reasoning_tokens: int

  StdUsage = object
    input_tokens: int
    output_tokens: int
    total_tokens: int
    input_tokens_details: StdInputDetails
    output_tokens_details: StdOutputDetails

  StdResult = object
    id: string
    `object`: string
    created_at: float
    completed_at: Option[int64]
    background: bool
    status: string
    error: Option[StdError]
    incomplete_details: Option[StdIncomplete]
    model: string
    output: seq[StdItem]
    previous_response_id: Option[string]
    service_tier: string
    usage: Option[StdUsage]
    metadata: JsonNode
    reasoning: JsonNode

proc stdFirstTextLocation(x: StdResult): tuple[outputIndex, partIndex: int] =
  for outputIndex in 0..<x.output.len:
    if x.output[outputIndex].`type` == "message" and
        x.output[outputIndex].content.isSome:
      for partIndex in 0..<x.output[outputIndex].content.get.len:
        if x.output[outputIndex].content.get[partIndex].`type` == "output_text" and
            x.output[outputIndex].content.get[partIndex].text.len > 0:
          return (outputIndex, partIndex)
  raise newException(ValueError, "no output text")

proc stdFirstText(x: StdResult): lent string =
  let location = stdFirstTextLocation(x)
  result = x.output[location.outputIndex].content.get[location.partIndex].text

proc stdFirstCallArgs(x: StdResult): lent string =
  for i in 0..<x.output.len:
    if x.output[i].`type` == "function_call":
      if x.output[i].arguments.isSome:
        return x.output[i].arguments.get
  raise newException(ValueError, "no function calls")

# --- std/json side B: direct tree access of only the needed fields -----------

type
  Direct = object
    text, callArgs: string
    inputTokens, outputTokens, cachedTokens, reasoningTokens, totalTokens: int
    hasUsage: bool

func strOrEmpty(n: JsonNode): string {.inline.} =
  if n != nil and n.kind == JString: n.str else: ""

func intOrZero(n: JsonNode): int {.inline.} =
  if n != nil and n.kind == JInt: n.num.int else: 0

func objOrNull(n: JsonNode): JsonNode {.inline.} =
  if n != nil and n.kind == JObject: n else: nil

proc extractDirect(body: string; dst: var Direct) =
  let root = parseJson(body)
  let output = root.getOrDefault("output")
  if output != nil and output.kind == JArray:
    for item in items(output):
      let kind = strOrEmpty(item.getOrDefault("type"))
      if kind == "message" and dst.text.len == 0:
        let content = item.getOrDefault("content")
        if content != nil and content.kind == JArray:
          for part in items(content):
            if strOrEmpty(part.getOrDefault("type")) == "output_text":
              let text = strOrEmpty(part.getOrDefault("text"))
              if text.len > 0:
                dst.text = text
                break
      elif kind == "function_call" and dst.callArgs.len == 0:
        dst.callArgs = strOrEmpty(item.getOrDefault("arguments"))
  let usage = root.getOrDefault("usage").objOrNull()
  if usage != nil:
    dst.hasUsage = true
    dst.inputTokens = intOrZero(usage.getOrDefault("input_tokens"))
    dst.outputTokens = intOrZero(usage.getOrDefault("output_tokens"))
    dst.totalTokens = intOrZero(usage.getOrDefault("total_tokens"))
    let inputDetails = usage.getOrDefault("input_tokens_details").objOrNull()
    if inputDetails != nil:
      dst.cachedTokens = intOrZero(inputDetails.getOrDefault("cached_tokens"))
    let outputDetails = usage.getOrDefault("output_tokens_details").objOrNull()
    if outputDetails != nil:
      dst.reasoningTokens = intOrZero(outputDetails.getOrDefault("reasoning_tokens"))

# --- shared inner step: parse the first call's arguments JSON ----------------

type
  CallFilters = object
    min_amount: float
    currency: string
    statuses: seq[string]

  CallArgs = object
    query: string
    filters: CallFilters
    limit: int
    include_attachments: bool

var checksum: int64

template consume(text, args: string; inputTokens, outputTokens, cachedTokens,
    reasoningTokens, totalTokens: int) =
  checksum += text.len.int64 + args.len.int64 +
    inputTokens.int64 + outputTokens.int64 + cachedTokens.int64 +
    reasoningTokens.int64 + totalTokens.int64

proc main() =
  let body = makeResponseBody()
  echo "body: ", body.len, " bytes, output items: 4 (reasoning, message x",
    PartCount, " parts, function_call, web_search_call)"

  block correctness:
    var r: ResponseResult
    r = fromJson(body, ResponseResult)
    doAssert r.id == "resp_9f3a7c"
    let std = parseJson(body).to(StdResult)
    var direct: Direct
    extractDirect(body, direct)
    doAssert firstText(r) == stdFirstText(std)
    doAssert firstText(r) == direct.text
    doAssert firstCallArgs(r) == stdFirstCallArgs(std)
    doAssert firstCallArgs(r) == direct.callArgs
    doAssert inputTokens(r) == std.usage.get.input_tokens
    doAssert inputTokens(r) == direct.inputTokens
    doAssert cachedInputTokens(r) == std.usage.get.input_tokens_details.cached_tokens
    doAssert cachedInputTokens(r) == direct.cachedTokens
    doAssert reasoningTokens(r) == direct.reasoningTokens
    doAssert totalTokens(r) == direct.totalTokens
    doAssert direct.hasUsage
    doAssert r.output[3].`type` == ResponseOutputKind.web_search_call
    doAssert ($r.output[3].extraFieldsOf()).len > 0
    doAssert std.output[3].`type` == "web_search_call"
    doAssert std.metadata["job"].getStr == "42"
    var argsA: CallArgs
    doAssert (parseFirstCallArgs(r, argsA) and
        argsA.query.len > 0 and argsA.limit == 25)
    let argsB = parseJson(stdFirstCallArgs(std)).to(CallArgs)
    doAssert argsA.query == argsB.query and argsA.limit == argsB.limit
    echo "parity checks: OK"

  var
    jsonxResult: ResponseResult
    stdResult: StdResult
    directResult: Direct
    parsedArgs: CallArgs

  proc jsonxTyped() =
    jsonxResult = fromJson(body, ResponseResult)
    consume(firstText(jsonxResult), firstCallArgs(jsonxResult),
      inputTokens(jsonxResult), outputTokens(jsonxResult),
      cachedInputTokens(jsonxResult), reasoningTokens(jsonxResult),
      totalTokens(jsonxResult))

  proc stdTyped() =
    stdResult = parseJson(body).to(StdResult)
    consume(stdFirstText(stdResult), stdFirstCallArgs(stdResult),
      stdResult.usage.get.input_tokens, stdResult.usage.get.output_tokens,
      stdResult.usage.get.input_tokens_details.cached_tokens,
      stdResult.usage.get.output_tokens_details.reasoning_tokens,
      stdResult.usage.get.total_tokens)

  proc stdDirect() =
    directResult = default(Direct)
    extractDirect(body, directResult)
    consume(directResult.text, directResult.callArgs, directResult.inputTokens,
      directResult.outputTokens, directResult.cachedTokens,
      directResult.reasoningTokens, directResult.totalTokens)

  proc stdParseOnly() =
    let tree = parseJson(body)
    checksum += tree.len.int64

  proc jsonxParseArgs() =
    discard parseFirstCallArgs(jsonxResult, parsedArgs)
    checksum += parsedArgs.limit.int64

  proc stdParseArgs() =
    parsedArgs = parseJson(stdFirstCallArgs(stdResult)).to(CallArgs)
    checksum += parsedArgs.limit.int64

  proc measure(name: string; op: proc(); baseline: float = 0): float =
    for _ in 1..WarmupIters:
      op()
    let t0 = getMonoTime()
    op()
    let one = (getMonoTime() - t0).inNanoseconds.float
    let iters = max(1, int(0.4e9 / max(one, 1.0)))
    var best = 0'i64
    for _ in 1..3:
      let r0 = getMonoTime()
      for _ in 1..iters:
        op()
      let dt = (getMonoTime() - r0).inNanoseconds
      if best == 0 or dt < best:
        best = dt
    let ns = best.float / iters.float
    let ratio = if baseline > 0: ns / baseline else: 1.0
    echo &"{name:<26} {iters:>7} iters  {ns:>9.0f} ns/op  " &
      &"{body.len.float * iters.float / best.float * 1e3:>7.1f} MB/s  " &
      &"{ratio:>5.2f}x"
    result = ns

  echo ""
  echo "-- timing (best of 3, ~0.4s per round) --"
  let jsonxNs = measure("jsonx typed", jsonxTyped)
  discard measure("std/json typed (to)", stdTyped, jsonxNs)
  discard measure("std/json direct", stdDirect, jsonxNs)
  discard measure("std/json parse only", stdParseOnly, jsonxNs)
  echo ""
  echo "-- inner step: parse call arguments --"
  let argsNs = measure("jsonx parseFirstCallArgs", jsonxParseArgs)
  discard measure("std parseJson+to(args)", stdParseArgs, argsNs)
  echo ""
  echo "checksum: ", checksum

main()
