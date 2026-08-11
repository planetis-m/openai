## Helpers for creating and reading OpenAI Responses API requests.

import relay
import jsonx
import ./[config, http]
import ./schema/responses_schema

export config
export responses_schema

const ResponsesPath = "/responses"

let
  formatText* = ResponseFormat(`type`: ResponseFormatType.text)
  formatJsonObject* = ResponseFormat(`type`: ResponseFormatType.json_object)

proc inputText*(text: sink string): ResponseInput =
  ## Creates a plain-text Responses API input.
  ResponseInput(kind: ResponseInputKind.text, text: text)

proc inputItems*(items: sink seq[RawJson]): ResponseInput =
  ## Creates an input from message, function-result, or other API items.
  ResponseInput(kind: ResponseInputKind.items, items: items)

proc partText*(text: sink string): ResponsePart =
  ## Creates an input text content part.
  ResponsePart(`type`: ResponsePartType.input_text, text: text)

proc partImageUrl*(url: sink string; detail = "auto"): ResponsePart =
  ## Creates an image input content part backed by a URL or data URL.
  result = ResponsePart(
    `type`: ResponsePartType.input_image,
    image_url: url,
    detail: detail
  )

proc partImageFile*(fileId: sink string; detail = "auto"): ResponsePart =
  ## Creates an image input content part backed by an uploaded file.
  result = ResponsePart(
    `type`: ResponsePartType.input_image,
    file_id: fileId,
    detail: detail
  )

proc partFileUrl*(url: sink string): ResponsePart =
  ## Creates a file input content part backed by a URL.
  ResponsePart(`type`: ResponsePartType.input_file, file_url: url)

proc partFileId*(fileId: sink string): ResponsePart =
  ## Creates a file input content part backed by an uploaded file.
  ResponsePart(`type`: ResponsePartType.input_file, file_id: fileId)

proc partFileData*(data, filename: sink string): ResponsePart =
  ## Creates a file input content part from encoded file data.
  result = ResponsePart(
    `type`: ResponsePartType.input_file,
    file_data: data,
    filename: filename
  )

proc contentText*(text: sink string): ResponseContent =
  ## Creates message or function output content from text.
  result = ResponseContent(
    kind: ResponseContentKind.text,
    text: text
  )

proc contentParts*(
    parts: sink seq[ResponsePart]): ResponseContent =
  ## Creates message or function output content from typed parts.
  result = ResponseContent(
    kind: ResponseContentKind.parts,
    parts: parts
  )

proc messageText*(role: ResponseRole;
    text: sink string): ResponseMessage =
  ## Creates a message input item with string content.
  result = ResponseMessage(
    role: role,
    content: contentText(text)
  )

proc messageParts*(role: ResponseRole;
    parts: sink seq[ResponsePart]): ResponseMessage =
  ## Creates a message input item with typed content parts.
  result = ResponseMessage(
    role: role,
    content: contentParts(parts)
  )

proc functionOutput*(callId: sink string;
    output: sink string): ResponseFunctionOutput =
  ## Creates a function-call output item containing text.
  result = ResponseFunctionOutput(
    `type`: ResponseFunctionOutputType.function_call_output,
    call_id: callId,
    output: contentText(output)
  )

proc functionOutputParts*(callId: sink string;
    output: sink seq[ResponsePart]): ResponseFunctionOutput =
  ## Creates a function-call output item containing typed content parts.
  result = ResponseFunctionOutput(
    `type`: ResponseFunctionOutputType.function_call_output,
    call_id: callId,
    output: contentParts(output)
  )

proc functionOutputJson*[T](callId: sink string;
    output: T): ResponseFunctionOutput =
  ## Creates a function-call output item containing JSON encoded as text.
  result = ResponseFunctionOutput(
    `type`: ResponseFunctionOutputType.function_call_output,
    call_id: callId,
    output: contentText(toJson(output))
  )

proc functionTool*(name: sink string; description: sink string = "";
    parameters: sink RawJson = EmptyResponseObjectSchema;
    strict = true): ResponseFunctionTool =
  ## Creates a function tool definition.
  result = ResponseFunctionTool(
    `type`: ResponseToolType.function,
    name: name,
    description: description,
    parameters: parameters,
    strict: strict
  )

proc functionTool*[TSchema](name: sink string; description: sink string;
    parametersSchema: TSchema; strict = true): ResponseFunctionTool =
  ## Creates a function tool definition from a serializable schema value.
  functionTool(name, description, RawJson(toJson(parametersSchema)), strict)

proc toolChoiceFunction*(name: sink string): ResponseToolChoice =
  ## Requires the model to call the named function tool.
  ResponseToolChoice(`type`: ResponseToolType.function, name: name)

proc formatJsonSchema*(name: sink string; schema: sink RawJson;
    description: sink string = ""; strict = true): ResponseFormat =
  ## Creates a structured-output JSON Schema format.
  result = ResponseFormat(
    `type`: ResponseFormatType.json_schema,
    name: name,
    description: description,
    schema: schema,
    strict: strict
  )

proc formatJsonSchema*[TSchema](name: sink string; schema: TSchema;
    description: sink string = ""; strict = true): ResponseFormat =
  ## Creates a structured-output format from a serializable schema value.
  formatJsonSchema(name, RawJson(toJson(schema)), description, strict)

proc responseCreate*(model: sink string; input: sink ResponseInput;
    instructions: sink string = ""; maxOutputTokens = 0;
    reasoning = ResponseReasoning(); text = ResponseTextConfig();
    tools: sink seq[RawJson] = @[]; toolChoice = RawJson("");
    previousResponseId: sink string = ""; background = false;
    parallelToolCalls = true; store = true; stream = false;
    promptCacheKey: sink string = "";
    promptCacheOptions = PromptCacheOptions();
    temperature = 1.0; topLogprobs = 0;
    topP = 1.0): ResponseParams =
  ## Creates parameters for `POST /responses` without deprecated fields.
  result = ResponseParams(
    model: model,
    input: input,
    instructions: instructions,
    max_output_tokens: maxOutputTokens,
    reasoning: reasoning,
    text: text,
    tools: tools,
    tool_choice: toolChoice,
    previous_response_id: previousResponseId,
    background: background,
    parallel_tool_calls: parallelToolCalls,
    store: store,
    stream: stream,
    prompt_cache_key: promptCacheKey,
    prompt_cache_options: promptCacheOptions,
    temperature: temperature,
    top_logprobs: topLogprobs,
    top_p: topP
  )

proc responseRequest*(cfg: OpenAIConfig; params: ResponseParams;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  ## Builds a Responses API HTTP request.
  request(cfg, hvPost, cfg.url & ResponsesPath, params,
    requestId, timeoutMs, headers)

proc responseAdd*(batch: var RequestBatch; cfg: OpenAIConfig;
    params: ResponseParams; requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  ## Adds a Responses API HTTP request to a Relay batch.
  requestAdd(batch, cfg, hvPost, cfg.url & ResponsesPath, params,
    requestId, timeoutMs, headers)

proc responseParse*(body: string; dst: out ResponseResult): bool =
  ## Parses a non-streaming Responses API result.
  dst = default(ResponseResult)
  try:
    dst = fromJson(body, ResponseResult)
    result = true
  except CatchableError:
    result = false

proc raiseResponseAccessorError(message: string) {.noinline, noreturn.} =
  raise newException(ValueError, message)

proc raiseInvalidOutputIndex(i, outputCount: int) {.inline, noreturn.} =
  raiseResponseAccessorError("output item index " & $i &
    " out of range for " & $outputCount & " output items")

proc raiseNoOutputText() {.inline, noreturn.} =
  raiseResponseAccessorError("response has no output text")

proc ensureOutputIndex(outputCount, i: int) {.inline.} =
  if i < 0 or i >= outputCount:
    raiseInvalidOutputIndex(i, outputCount)

proc firstNonEmptyTextPartLocation(
    x: ResponseResult): tuple[outputIndex, partIndex: int] =
  for outputIndex in 0..<x.output.len:
    for partIndex in 0..<x.output[outputIndex].content.len:
      let part = x.output[outputIndex].content[partIndex]
      if part.`type` == ResponseOutputPartType.output_text and part.text.len > 0:
        return (outputIndex, partIndex)
  raiseNoOutputText()

proc createdAt*(x: ResponseResult): float {.inline.} =
  x.created_at

proc outputItem*(x: ResponseResult;
    outputIndex: int): lent ResponseOutput {.inline.} =
  ## Returns output item `outputIndex` after validating the index.
  ensureOutputIndex(x.output.len, outputIndex)
  result = x.output[outputIndex]

proc outputItem*(x: var ResponseResult;
    outputIndex: int): var ResponseOutput {.inline.} =
  ## Returns a mutable view of output item `outputIndex` after validating the index.
  ensureOutputIndex(x.output.len, outputIndex)
  result = x.output[outputIndex]

proc firstText*(x: ResponseResult): lent string =
  ## Returns the first non-empty output-text part in response order.
  let location = firstNonEmptyTextPartLocation(x)
  result = x.output[location.outputIndex].content[location.partIndex].text

proc parseFirstTextJson*[T](x: ResponseResult; dst: out T): bool =
  ## Parses the first non-empty output text in response order as `T`.
  dst = default(T)
  try:
    dst = fromJson(x.firstText(), T)
    result = true
  except CatchableError:
    result = false

proc outputText*(x: ResponseResult): string =
  ## Returns all output-text parts concatenated in response order,
  ## or an empty string when the response has no output text.
  var textLen = 0
  for item in x.output:
    for part in item.content:
      if part.`type` == ResponseOutputPartType.output_text:
        textLen += part.text.len

  result = newStringOfCap(textLen)
  for item in x.output:
    for part in item.content:
      if part.`type` == ResponseOutputPartType.output_text:
        result.add(part.text)

proc functionCalls*(x: ResponseResult): seq[ResponseOutput] =
  ## Returns all function-call output items in response order.
  result = @[]
  for item in x.output:
    if item.`type` == ResponseOutputKind.function_call:
      result.add(item)

proc hasFunctionCalls*(x: ResponseResult): bool =
  ## Returns whether the response contains a function-call output item.
  result = false
  for item in x.output:
    if item.`type` == ResponseOutputKind.function_call:
      return true

proc firstCallId*(x: ResponseResult): lent string =
  for i in 0..<x.output.len:
    if x.output[i].`type` == ResponseOutputKind.function_call:
      return x.output[i].call_id
  raiseResponseAccessorError("response has no function calls")

proc firstCallName*(x: ResponseResult): lent string =
  for i in 0..<x.output.len:
    if x.output[i].`type` == ResponseOutputKind.function_call:
      return x.output[i].name
  raiseResponseAccessorError("response has no function calls")

proc firstCallArgs*(x: ResponseResult): lent string =
  for i in 0..<x.output.len:
    if x.output[i].`type` == ResponseOutputKind.function_call:
      return x.output[i].arguments
  raiseResponseAccessorError("response has no function calls")

proc parseFirstCallArgs*[T](x: ResponseResult; dst: out T): bool =
  ## Parses the first function call's JSON arguments as `T`.
  dst = default(T)
  try:
    dst = fromJson(x.firstCallArgs(), T)
    result = true
  except CatchableError:
    result = false

proc hasError*(x: ResponseResult): bool {.inline.} =
  x.error.isSome

proc errorOf*(x: ResponseResult): lent ResponseError {.inline.} =
  if x.error.isNone:
    raiseResponseAccessorError("response has no error data")
  result = x.error.get

proc hasUsage*(x: ResponseResult): bool {.inline.} =
  x.usage.isSome

proc usageOf(x: ResponseResult): lent ResponseUsage {.inline.} =
  if x.usage.isNone:
    raiseResponseAccessorError("response has no usage data")
  result = x.usage.get

proc inputTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().input_tokens

proc cachedInputTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().input_tokens_details.cached_tokens

proc cacheWriteTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().input_tokens_details.cache_write_tokens

proc outputTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().output_tokens

proc reasoningTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().output_tokens_details.reasoning_tokens

proc totalTokens*(x: ResponseResult): int {.inline.} =
  x.usageOf().total_tokens
