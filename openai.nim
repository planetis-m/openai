import relay
import jsonx
import openai_schema

export openai_schema

type
  ResponsesCreateParams* = OpenAIChatCompletionsIn
  ResponsesCreateResult* = OpenAIChatCompletionOut

  EndpointConfig* = object
    url*: string
    apiKey*: string

proc textPart*(text: string): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.text,
    text: text
  )

proc imageUrlPart*(url: string;
    detail = ImageDetail.auto): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.image_url,
    image_url: ImageUrl(
      url: url,
      detail: detail
    )
  )

proc inputAudioPart*(data: string;
    format: InputAudioFormat): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.input_audio,
    input_audio: InputAudio(
      data: data,
      format: format
    )
  )

proc textContent*(text: string): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.text,
    text: text
  )

proc partsContent*(parts: openArray[ChatCompletionContentPart]): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.parts,
    parts: @parts
  )

proc msgSystem*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.system,
    content: textContent(text),
    name: name
  )

proc msgUserText*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: textContent(text),
    name: name
  )

proc msgUserParts*(parts: openArray[ChatCompletionContentPart];
    name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: partsContent(parts),
    name: name
  )

proc msgAssistant*(text: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.assistant,
    content: textContent(text),
    name: name
  )

proc msgTool*(text: string; toolCallId: string; name = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.tool,
    content: textContent(text),
    name: name,
    tool_call_id: toolCallId
  )

proc functionTool*(name: string; description = ""): ChatTool =
  ChatTool(
    `type`: ChatToolType.function,
    function: FunctionDefinition(
      name: name,
      description: description
    )
  )

proc responseFormatText*(): ResponseFormat =
  ResponseFormat(`type`: ResponseFormatType.text)

proc responseFormatJsonObject*(): ResponseFormat =
  ResponseFormat(`type`: ResponseFormatType.json_object)

proc responseFormatJsonSchema*(): ResponseFormat =
  ResponseFormat(`type`: ResponseFormatType.json_schema)

proc responseFormatRegex*(): ResponseFormat =
  ResponseFormat(`type`: ResponseFormatType.regex)

proc responsesCreateParams*(model: string; messages: openArray[ChatMessage];
    stream = false; temperature = 1.0; maxTokens = 0;
    tools: openArray[ChatTool] = [];
    toolChoice = ToolChoice.auto;
    responseFormat = responseFormatText()): ResponsesCreateParams =
  ResponsesCreateParams(
    model: model,
    messages: @messages,
    stream: stream,
    temperature: temperature,
    max_tokens: maxTokens,
    tools: @tools,
    tool_choice: toolChoice,
    response_format: responseFormat
  )

proc withDefaultHeaders(cfg: EndpointConfig;
    headers: sink HttpHeaders = emptyHttpHeaders()): HttpHeaders =
  result = headers
  result["Authorization"] = "Bearer " & cfg.apiKey
  result["Content-Type"] = "application/json"

proc responsesCreateRequest*(cfg: EndpointConfig; params: ResponsesCreateParams;
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

proc addResponsesCreate*(batch: var RequestBatch; cfg: EndpointConfig;
    params: ResponsesCreateParams; requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  batch.addRequest(
    verb = hvPost,
    url = cfg.url,
    headers = cfg.withDefaultHeaders(headers),
    body = toJson(params),
    requestId = requestId,
    timeoutMs = timeoutMs
  )

proc tryDecodeResponsesCreate*(body: string; dst: var ResponsesCreateResult): bool =
  try:
    dst = fromJson(body, ResponsesCreateResult)
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

proc responseId*(x: ResponsesCreateResult): string {.inline.} =
  x.id

proc responseModel*(x: ResponsesCreateResult): string {.inline.} =
  x.model

proc usagePromptTokens*(x: ResponsesCreateResult): int {.inline.} =
  x.usage.prompt_tokens

proc usageCompletionTokens*(x: ResponsesCreateResult): int {.inline.} =
  x.usage.completion_tokens

proc usageTotalTokens*(x: ResponsesCreateResult): int {.inline.} =
  x.usage.total_tokens

proc choiceCount*(x: ResponsesCreateResult): int {.inline.} =
  x.choices.len

proc hasChoiceAt(x: ResponsesCreateResult; i: int): bool {.inline.} =
  i >= 0 and i < x.choices.len

proc finishReason*(x: ResponsesCreateResult; i = 0): string =
  if not x.hasChoiceAt(i):
    result = ""
  else:
    result = $x.choices[i].finish_reason

proc assistantText*(x: ResponsesCreateResult; i = 0): string =
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

proc assistantPartsText*(x: ResponsesCreateResult; i = 0): seq[string] =
  result = @[]
  if not x.hasChoiceAt(i):
    return
  let content = x.choices[i].message.content
  if content.kind != ChatCompletionAssistantContentKind.parts:
    return
  for part in content.parts:
    result.add(part.text)

proc toolCalls*(x: ResponsesCreateResult;
    i = 0): seq[ChatCompletionMessageToolCall] =
  if not x.hasChoiceAt(i):
    return @[]
  x.choices[i].message.tool_calls

proc firstToolCallName*(x: ResponsesCreateResult; i = 0): string =
  let calls = x.toolCalls(i)
  if calls.len == 0:
    return ""
  calls[0].function.name

proc firstToolCallArguments*(x: ResponsesCreateResult; i = 0): string =
  let calls = x.toolCalls(i)
  if calls.len == 0:
    return ""
  calls[0].function.arguments
