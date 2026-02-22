import relay
import jsonx
import openai_schema

export openai_schema

type
  ChatCreateParams* = OpenAIChatCompletionsIn
  ChatCreateResult* = OpenAIChatCompletionOut

  OpenAIConfig* = object
    url*: string
    apiKey*: string

proc partText*(text: string): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.text,
    text: text
  )

proc partImageUrl*(url: string;
    detail = ImageDetail.auto): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.image_url,
    image_url: ImageUrl(
      url: url,
      detail: detail
    )
  )

proc partInputAudio*(data: string;
    format: InputAudioFormat): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.input_audio,
    input_audio: InputAudio(
      data: data,
      format: format
    )
  )

proc contentText*(text: string): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.text,
    text: text
  )

proc contentParts*(parts: openArray[ChatCompletionContentPart]): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.parts,
    parts: @parts
  )

proc systemMessageText*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.system,
    content: contentText(text),
    name: name
  )

proc userMessageText*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: contentText(text),
    name: name
  )

proc userMessageParts*(parts: openArray[ChatCompletionContentPart];
    name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: contentParts(parts),
    name: name
  )

proc assistantMessageText*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.assistant,
    content: contentText(text),
    name: name
  )

proc toolMessageText*(text: string; toolCallId: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.tool,
    content: contentText(text),
    name: name,
    tool_call_id: toolCallId
  )

proc toolFunction*(name: string; description = ""): ChatTool =
  ChatTool(
    `type`: ChatToolType.function,
    function: FunctionDefinition(
      name: name,
      description: description
    )
  )

const
  formatText* = ResponseFormat(`type`: ResponseFormatType.text)
  formatJsonObject* = ResponseFormat(`type`: ResponseFormatType.json_object)
  formatJsonSchema* = ResponseFormat(`type`: ResponseFormatType.json_schema)
  formatRegex* = ResponseFormat(`type`: ResponseFormatType.regex)

proc chatCreate*(model: string; messages: openArray[ChatMessage];
    stream = false; temperature = 1.0; maxTokens = 0;
    tools: openArray[ChatTool] = [];
    toolChoice = ToolChoice.auto;
    responseFormat = formatText): ChatCreateParams =
  ChatCreateParams(
    model: model,
    messages: @messages,
    stream: stream,
    temperature: temperature,
    max_tokens: maxTokens,
    tools: @tools,
    tool_choice: toolChoice,
    response_format: responseFormat
  )

proc withDefaultHeaders(cfg: OpenAIConfig;
    headers: sink HttpHeaders = emptyHttpHeaders()): HttpHeaders =
  result = headers
  result["Authorization"] = "Bearer " & cfg.apiKey
  result["Content-Type"] = "application/json"

proc chatRequest*(cfg: OpenAIConfig; params: ChatCreateParams;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  RequestSpec(
    verb: hvPost,
    url: cfg.url,
    headers: cfg.withDefaultHeaders(headers),
    body: toJson(params),
    requestId: requestId,
    timeoutMs: timeoutMs
  )

proc chatAdd*(batch: var RequestBatch; cfg: OpenAIConfig;
    params: ChatCreateParams; requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  batch.addRequest(
    verb = hvPost,
    url = cfg.url,
    headers = cfg.withDefaultHeaders(headers),
    body = toJson(params),
    requestId = requestId,
    timeoutMs = timeoutMs
  )

proc chatParse*(body: string; dst: var ChatCreateResult): bool =
  try:
    dst = fromJson(body, ChatCreateResult)
    result = true
  except CatchableError:
    result = false

proc isHttpSuccess*(code: int): bool {.inline.} =
  code div 100 == 2

proc isRetriableTransport*(kind: TransportErrorKind): bool {.inline.} =
  case kind
  of teTimeout, teNetwork, teDns, teTls, teInternal:
    true
  of teNone, teCanceled, teProtocol:
    false

proc isRetriableStatus*(code: int): bool {.inline.} =
  case code
  of 408, 409, 425, 429:
    true
  else:
    code >= 500 and code <= 599

proc idOf*(x: ChatCreateResult): string {.inline.} =
  x.id

proc modelOf*(x: ChatCreateResult): string {.inline.} =
  x.model

proc promptTokens*(x: ChatCreateResult): int {.inline.} =
  x.usage.prompt_tokens

proc completionTokens*(x: ChatCreateResult): int {.inline.} =
  x.usage.completion_tokens

proc totalTokens*(x: ChatCreateResult): int {.inline.} =
  x.usage.total_tokens

proc choices*(x: ChatCreateResult): int {.inline.} =
  x.choices.len

proc hasChoiceAt(x: ChatCreateResult; i: int): bool {.inline.} =
  i >= 0 and i < x.choices.len

proc finish*(x: ChatCreateResult; i = 0): string =
  if not x.hasChoiceAt(i):
    result = ""
  else:
    result = $x.choices[i].finish_reason

proc firstText*(x: ChatCreateResult; i = 0): string =
  result = ""
  if not x.hasChoiceAt(i):
    return
  let content = x.choices[i].message.content
  case content.kind
  of ChatCompletionAssistantContentKind.text:
    result = content.text
  of ChatCompletionAssistantContentKind.parts:
    for part in content.parts:
      if part.text.len > 0:
        return part.text

proc allTextParts*(x: ChatCreateResult; i = 0): seq[string] =
  result = @[]
  if not x.hasChoiceAt(i):
    return
  let content = x.choices[i].message.content
  if content.kind != ChatCompletionAssistantContentKind.parts:
    return
  for part in content.parts:
    result.add(part.text)

proc calls*(x: ChatCreateResult;
    i = 0): seq[ChatCompletionMessageToolCall] =
  if not x.hasChoiceAt(i):
    return @[]
  x.choices[i].message.tool_calls

proc firstCallName*(x: ChatCreateResult; i = 0): string =
  let callList = x.calls(i)
  if callList.len == 0:
    return ""
  callList[0].function.name

proc firstCallArgs*(x: ChatCreateResult; i = 0): string =
  let callList = x.calls(i)
  if callList.len == 0:
    return ""
  callList[0].function.arguments
