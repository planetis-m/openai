import relay
import jsonx
import openai_schema

export openai_schema

const OpenAIApiUrl = "https://api.openai.com/v1/chat/completions"

type
  ChatCreateParams* = OpenAIChatCompletionsIn
  ChatCreateResult* = OpenAIChatCompletionOut

  OpenAIConfig* = object
    url*: string = OpenAIApiUrl
    apiKey*: string

proc partText*(text: sink string): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.text,
    text: text
  )

proc partImageUrl*(url: sink string;
    detail = ImageDetail.auto): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.image_url,
    image_url: ImageUrl(
      url: url,
      detail: detail
    )
  )

proc partInputAudio*(data: sink string;
    format: InputAudioFormat): ChatCompletionContentPart =
  ChatCompletionContentPart(
    `type`: ChatCompletionContentPartType.input_audio,
    input_audio: InputAudio(
      data: data,
      format: format
    )
  )

proc contentText*(text: sink string): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.text,
    text: text
  )

proc contentParts*(parts: sink seq[ChatCompletionContentPart]): ChatCompletionMessageContent =
  ChatCompletionMessageContent(
    kind: ChatCompletionInputContentKind.parts,
    parts: parts
  )

proc systemMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.system,
    content: contentText(text),
    name: name
  )

proc userMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: contentText(text),
    name: name
  )

proc userMessageParts*(parts: sink seq[ChatCompletionContentPart];
    name: sink string = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.user,
    content: contentParts(parts),
    name: name
  )

proc assistantMessageText*(text: sink string; name: sink string = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.assistant,
    content: contentText(text),
    name: name
  )

proc assistantMessageToolCalls*(toolCalls: sink seq[ChatCompletionMessageToolCall]): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.assistant,
    tool_calls: toolCalls
  )

proc toolMessageText*(text, toolCallId: sink string; name: sink string = ""): ChatMessage =
  ChatMessage(
    role: ChatMessageRole.tool,
    content: contentText(text),
    name: name,
    tool_call_id: toolCallId
  )

proc toolMessageJson*[T](value: T; toolCallId: sink string;
    name: sink string = ""): ChatMessage =
  result = toolMessageText(toJson(value), toolCallId, name)

proc toolFunction*(name: sink string; description: sink string = ""): ChatTool =
  ChatTool(
    `type`: ChatToolType.function,
    function: FunctionDefinition(
      name: name,
      description: description,
      parameters: EmptyFunctionParametersSchema
    )
  )

proc toolFunction*(name: sink string; description: sink string;
    parameters: sink string): ChatTool =
  ChatTool(
    `type`: ChatToolType.function,
    function: FunctionDefinition(
      name: name,
      description: description,
      parameters: parameters
    )
  )

proc toolFunction*[TSchema](name: sink string; description: sink string;
    parametersSchema: TSchema): ChatTool =
  result = toolFunction(name, description, toJson(parametersSchema))

proc toolFunction*[TSchema](name: sink string;
    parametersSchema: TSchema): ChatTool =
  result = toolFunction(name, "", toJson(parametersSchema))

let
  formatText* = ResponseFormat(`type`: ResponseFormatType.text)
  formatJsonObject* = ResponseFormat(`type`: ResponseFormatType.json_object)
  formatRegex* = ResponseFormat(`type`: ResponseFormatType.regex)

proc formatJsonSchema*(name: sink string; schema: sink string;
    strict = true): ResponseFormat =
  ResponseFormat(
    `type`: ResponseFormatType.json_schema,
    json_schema: ResponseFormatJsonSchema(
      name: name,
      schema: schema,
      strict: strict
    )
  )

proc formatJsonSchema*[TSchema](name: sink string; schema: TSchema;
    strict = true): ResponseFormat =
  result = formatJsonSchema(name, toJson(schema), strict)

proc chatCreate*(model: sink string; messages: sink seq[ChatMessage];
    stream = false; temperature = 1.0; maxTokens = 0;
    tools: sink seq[ChatTool] = @[];
    toolChoice = ToolChoice.none;
    responseFormat = formatText): ChatCreateParams =
  ChatCreateParams(
    model: model,
    messages: messages,
    stream: stream,
    temperature: temperature,
    max_tokens: maxTokens,
    tools: tools,
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
  result = code div 100 == 2

proc idOf*(x: ChatCreateResult): lent string {.inline.} =
  result = x.id

proc modelOf*(x: ChatCreateResult): lent string {.inline.} =
  result = x.model

proc promptTokens*(x: ChatCreateResult): int {.inline.} =
  result = x.usage.prompt_tokens

proc completionTokens*(x: ChatCreateResult): int {.inline.} =
  result = x.usage.completion_tokens

proc totalTokens*(x: ChatCreateResult): int {.inline.} =
  result = x.usage.total_tokens

proc choices*(x: ChatCreateResult): int {.inline.} =
  result = x.choices.len

proc hasChoiceAt(x: ChatCreateResult; i: int): bool {.inline.} =
  result = i >= 0 and i < x.choices.len

proc finish*(x: ChatCreateResult; i = 0): FinishReason =
  if not x.hasChoiceAt(i):
    result = FinishReason.unknown
  else:
    result = x.choices[i].finish_reason

proc firstText*(x: ChatCreateResult; i = 0): string =
  result = ""
  if x.hasChoiceAt(i):
    let content = x.choices[i].message.content
    case content.kind
    of ChatCompletionAssistantContentKind.text:
      result = content.text
    of ChatCompletionAssistantContentKind.parts:
      for part in content.parts:
        if result.len == 0 and part.text.len > 0:
          return part.text

proc parseFirstTextJson*[T](x: ChatCreateResult; dst: var T; i = 0): bool =
  result = false
  let text = x.firstText(i)
  if text.len > 0:
    try:
      dst = fromJson(text, T)
      result = true
    except CatchableError:
      result = false

proc allTextParts*(x: ChatCreateResult; i = 0): seq[string] =
  result = @[]
  if x.hasChoiceAt(i):
    let content = x.choices[i].message.content
    if content.kind == ChatCompletionAssistantContentKind.parts:
      for part in content.parts:
        result.add(part.text)

proc calls*(x: ChatCreateResult; i = 0): seq[ChatCompletionMessageToolCall] =
  result = @[]
  if x.hasChoiceAt(i):
    result = x.choices[i].message.tool_calls

proc hasToolCalls*(x: ChatCreateResult; i = 0): bool =
  result = false
  if x.hasChoiceAt(i):
    result = x.choices[i].message.tool_calls.len > 0

proc firstCallId*(x: ChatCreateResult; i = 0): string =
  result = ""
  if x.hasToolCalls(i):
    result = x.choices[i].message.tool_calls[0].id

proc firstCallName*(x: ChatCreateResult; i = 0): string =
  result = ""
  if x.hasToolCalls(i):
    result = x.choices[i].message.tool_calls[0].function.name

proc firstCallArgs*(x: ChatCreateResult; i = 0): string =
  result = ""
  if x.hasToolCalls(i):
    result = x.choices[i].message.tool_calls[0].function.arguments
