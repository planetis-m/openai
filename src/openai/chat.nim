## Helpers for creating and reading OpenAI Chat Completions requests.

import relay
import jsonx
import ./[config, http]
import ./schema/chat_schema

export config
export chat_schema

const ChatCompletionsPath = "/chat/completions"

proc partText*(text: sink string): ChatInputPart =
  ## Creates a text content part.
  result = ChatInputPart(
    `type`: ChatInputPartType.text,
    text: text
  )

proc partImageUrl*(url: sink string;
    detail = ChatImageDetail.auto): ChatInputPart =
  ## Creates an image content part backed by a URL or data URL.
  result = ChatInputPart(
    `type`: ChatInputPartType.image_url,
    image_url: ChatImageUrl(
      url: url,
      detail: detail
    )
  )

proc partInputAudio*(data: sink string;
    format: ChatAudioFormat): ChatInputPart =
  ## Creates an encoded audio content part.
  result = ChatInputPart(
    `type`: ChatInputPartType.input_audio,
    input_audio: ChatInputAudio(
      data: data,
      format: format
    )
  )

proc contentText*(text: sink string): ChatInputContent =
  ## Creates message content from text.
  result = ChatInputContent(
    kind: ChatInputContentKind.text,
    text: text
  )

proc contentParts*(parts: sink seq[ChatInputPart]): ChatInputContent =
  ## Creates message content from typed parts.
  result = ChatInputContent(
    kind: ChatInputContentKind.parts,
    parts: parts
  )

proc systemMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ## Creates a system message with text content.
  result = ChatMessage(
    role: ChatMessageRole.system,
    content: contentText(text),
    name: name
  )

proc developerMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ## Creates a developer message with text content.
  result = ChatMessage(
    role: ChatMessageRole.developer,
    content: contentText(text),
    name: name
  )

proc userMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ## Creates a user message with text content.
  result = ChatMessage(
    role: ChatMessageRole.user,
    content: contentText(text),
    name: name
  )

proc userMessageParts*(parts: sink seq[ChatInputPart];
    name: sink string = ""): ChatMessage =
  ## Creates a user message with typed content parts.
  result = ChatMessage(
    role: ChatMessageRole.user,
    content: contentParts(parts),
    name: name
  )

proc assistantMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ## Creates an assistant message with text content.
  result = ChatMessage(
    role: ChatMessageRole.assistant,
    content: contentText(text),
    name: name
  )

proc assistantMessageToolCalls*(
    toolCalls: sink seq[ChatToolCall]): ChatMessage =
  ## Creates an assistant message containing function calls.
  result = ChatMessage(
    role: ChatMessageRole.assistant,
    tool_calls: toolCalls
  )

proc toolMessageText*(text, toolCallId: sink string; name: sink string = ""): ChatMessage =
  ## Creates a function result message containing text.
  result = ChatMessage(
    role: ChatMessageRole.tool,
    content: contentText(text),
    name: name,
    tool_call_id: toolCallId
  )

proc toolMessageJson*[T](value: T; toolCallId: sink string;
    name: sink string = ""): ChatMessage =
  ## Creates a function result message containing JSON encoded as text.
  toolMessageText(toJson(value), toolCallId, name)

proc functionTool*(name: sink string; description: sink string = "";
    strict = true): ChatTool =
  ## Creates a function tool with an empty object parameter schema.
  result = ChatTool(
    `type`: ChatToolType.function,
    function: ChatFunctionDefinition(
      name: name,
      description: description,
      parameters: EmptyFunctionParametersSchema,
      strict: strict
    )
  )

proc functionTool*(name: sink string; description: sink string;
    parameters: sink RawJson; strict = true): ChatTool =
  ## Creates a function tool from a raw JSON parameter schema.
  result = ChatTool(
    `type`: ChatToolType.function,
    function: ChatFunctionDefinition(
      name: name,
      description: description,
      parameters: parameters,
      strict: strict
    )
  )

proc functionTool*[TSchema](name: sink string; description: sink string;
    parametersSchema: TSchema; strict = true): ChatTool =
  ## Creates a function tool from a serializable parameter schema.
  functionTool(name, description, RawJson(toJson(parametersSchema)), strict)

proc functionTool*[TSchema](name: sink string; parametersSchema: TSchema;
    strict = true): ChatTool =
  ## Creates a function tool without a description.
  functionTool(name, "", RawJson(toJson(parametersSchema)), strict)

proc toolChoiceFunction*(name: sink string): ChatToolChoice =
  ## Requires the model to call the named function tool.
  ChatToolChoice(
    `type`: ChatToolType.function,
    function: ChatNamedFunction(name: name)
  )

let
  formatText* = ChatFormat(`type`: ChatFormatType.text)
  formatJsonObject* = ChatFormat(`type`: ChatFormatType.json_object)

proc formatJsonSchema*(name: sink string; schema: sink RawJson;
    description: sink string = ""; strict = true): ChatFormat =
  ## Creates a structured-output JSON Schema format.
  result = ChatFormat(
    `type`: ChatFormatType.json_schema,
    json_schema: ChatJsonSchemaFormat(
      name: name,
      description: description,
      schema: schema,
      strict: strict
    )
  )

proc formatJsonSchema*[TSchema](name: sink string; schema: TSchema;
    description: sink string = ""; strict = true): ChatFormat =
  ## Creates a structured-output format from a serializable schema.
  formatJsonSchema(name, RawJson(toJson(schema)), description, strict)

proc chatCreate*(model: sink string; messages: sink seq[ChatMessage];
    stream = false; temperature = 1.0;
    maxCompletionTokens = 0;
    reasoningEffort = ChatReasoningEffort.unspecified;
    tools: sink seq[ChatTool] = @[];
    toolChoice = RawJson(""); responseFormat = formatText;
    parallelToolCalls = true; metadata: sink RawJson = RawJson("");
    promptCacheKey: sink string = "";
    promptCacheOptions = PromptCacheOptions();
    safetyIdentifier: sink string = ""; serviceTier: sink string = "";
    store = false): ChatParams =
  ## Creates Chat Completions parameters without deprecated request fields.
  result = ChatParams(
    model: model,
    messages: messages,
    stream: stream,
    temperature: temperature,
    max_completion_tokens: maxCompletionTokens,
    reasoning_effort: reasoningEffort,
    tools: tools,
    tool_choice: toolChoice,
    response_format: responseFormat,
    parallel_tool_calls: parallelToolCalls,
    metadata: metadata,
    prompt_cache_key: promptCacheKey,
    prompt_cache_options: promptCacheOptions,
    safety_identifier: safetyIdentifier,
    service_tier: serviceTier,
    store: store
  )

proc chatRequest*(cfg: OpenAIConfig; params: ChatParams;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  ## Builds a Chat Completions HTTP request.
  request(cfg, hvPost, cfg.url & ChatCompletionsPath, params,
    requestId, timeoutMs, headers)

proc chatAdd*(batch: var RequestBatch; cfg: OpenAIConfig;
    params: ChatParams; requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  ## Adds a Chat Completions HTTP request to a Relay batch.
  requestAdd(batch, cfg, hvPost, cfg.url & ChatCompletionsPath, params,
    requestId, timeoutMs, headers)

proc chatParse*(body: string; dst: out ChatResult): bool =
  ## Parses a non-streaming Chat Completions result.
  try:
    dst = fromJson(body, ChatResult)
    result = true
  except CatchableError:
    dst = default(ChatResult)
    result = false

proc raiseAccessorValueError(message: string) {.noinline, noreturn.} =
  raise newException(ValueError, message)

proc raiseInvalidChoiceIndex(i, choiceCount: int) {.inline, noreturn.} =
  raiseAccessorValueError("choice index " & $i &
    " out of range for " & $choiceCount & " choices")

proc raiseNoFunctionCallsAtChoice(i: int) {.inline, noreturn.} =
  raiseAccessorValueError("choice index " & $i & " has no function calls")

proc raiseNoTextPartsAtChoice(i: int) {.inline, noreturn.} =
  raiseAccessorValueError("choice index " & $i & " has no text parts")

proc ensureChoiceIndex(choiceCount, i: int) {.inline.} =
  if i < 0 or i >= choiceCount:
    raiseInvalidChoiceIndex(i, choiceCount)

proc firstNonEmptyTextPartIndex(content: ChatAssistantContent; i: int): int =
  if content.parts.len == 0:
    raiseNoTextPartsAtChoice(i)
  result = 0
  for partIdx in 0 ..< content.parts.len:
    if content.parts[partIdx].text.len > 0:
      result = partIdx
      return result

proc createdAt*(x: ChatResult): int64 {.inline.} =
  result = x.created

proc hasUsage*(x: ChatResult): bool {.inline.} =
  x.usage.isSome

proc usageOf*(x: ChatResult): lent ChatUsage {.inline.} =
  if x.usage.isNone:
    raiseAccessorValueError("chat completion has no usage data")
  result = x.usage.get

proc inputTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().prompt_tokens

proc cachedInputTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().prompt_tokens_details.cached_tokens

proc cacheWriteTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().prompt_tokens_details.cache_write_tokens

proc outputTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().completion_tokens

proc reasoningTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().completion_tokens_details.reasoning_tokens

proc totalTokens*(x: ChatResult): int {.inline.} =
  x.usageOf().total_tokens

proc finish*(x: ChatResult; i = 0): ChatFinishReason {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  result = x.choices[i].finish_reason

proc firstText*(x: ChatResult; i = 0): lent string =
  ensureChoiceIndex(x.choices.len, i)
  case x.choices[i].message.content.kind
  of ChatAssistantContentKind.none:
    raiseAccessorValueError("choice index " & $i & " has no content")
  of ChatAssistantContentKind.text:
    result = x.choices[i].message.content.text
  of ChatAssistantContentKind.parts:
    let partIdx = firstNonEmptyTextPartIndex(x.choices[i].message.content, i)
    result = x.choices[i].message.content.parts[partIdx].text

proc parseFirstTextJson*[T](x: ChatResult; dst: out T; i = 0): bool =
  try:
    dst = fromJson(x.firstText(i), T)
    result = true
  except CatchableError:
    dst = default(T)
    result = false

proc outputText*(x: ChatResult; i = 0): string =
  ## Returns the completion text of choice `i`, concatenating text parts
  ## when necessary, or an empty string when the choice has no content.
  ensureChoiceIndex(x.choices.len, i)
  case x.choices[i].message.content.kind
  of ChatAssistantContentKind.none:
    result = ""
  of ChatAssistantContentKind.text:
    result = x.choices[i].message.content.text
  of ChatAssistantContentKind.parts:
    result = ""
    for part in x.choices[i].message.content.parts:
      result.add(part.text)

proc functionCalls*(x: ChatResult;
    i = 0): lent seq[ChatToolCall] {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  result = x.choices[i].message.tool_calls

proc functionCalls*(x: var ChatResult;
    i = 0): var seq[ChatToolCall] {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  result = x.choices[i].message.tool_calls

proc hasFunctionCalls*(x: ChatResult; i = 0): bool =
  ensureChoiceIndex(x.choices.len, i)
  result = x.choices[i].message.tool_calls.len > 0

proc firstCallId*(x: ChatResult; i = 0): lent string {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  if x.choices[i].message.tool_calls.len == 0:
    raiseNoFunctionCallsAtChoice(i)
  result = x.choices[i].message.tool_calls[0].id

proc firstCallName*(x: ChatResult; i = 0): lent string {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  if x.choices[i].message.tool_calls.len == 0:
    raiseNoFunctionCallsAtChoice(i)
  result = x.choices[i].message.tool_calls[0].function.name

proc firstCallArgs*(x: ChatResult; i = 0): lent string {.inline.} =
  ensureChoiceIndex(x.choices.len, i)
  if x.choices[i].message.tool_calls.len == 0:
    raiseNoFunctionCallsAtChoice(i)
  result = x.choices[i].message.tool_calls[0].function.arguments

proc parseFirstCallArgs*[T](x: ChatResult; dst: out T; i = 0): bool =
  try:
    dst = fromJson(x.firstCallArgs(i), T)
    result = true
  except CatchableError:
    dst = default(T)
    result = false
