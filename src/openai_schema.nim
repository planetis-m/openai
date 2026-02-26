import jsonx
import jsonx/[parsejson, streams]

{.define: jsonxLenient.}

type
  ChatMessageRole* = enum
    system, user, assistant, tool

  ChatToolType* = enum
    function

  FinishReason* = enum
    unknown, stop, length, tool_calls, content_filter, malformed_function_call

  ImageDetail* = enum
    `auto`, low, high

  InputAudioFormat* = enum
    wav, mp3

  ToolChoice* = enum
    none, `auto`, required

  ResponseFormatType* = enum
    text, json_object, json_schema, regex

  # Output schema (trimmed common fields)
  ChatCompletionAssistantContentKind* = enum
    text, parts

  ChatCompletionContentPartText* = object
    `type`*: ChatCompletionContentPartType
    text*: string

  FunctionCall* = object
    name*: string
    arguments*: string

  ChatCompletionMessageToolCall* = object
    id*: string
    `type`*: ChatToolType
    function*: FunctionCall

  ChatCompletionAssistantContent* = object
    case kind*: ChatCompletionAssistantContentKind
    of text:
      text*: string
    of parts:
      parts*: seq[ChatCompletionContentPartText]

  ChatCompletionAssistantMessage* = object
    role*: ChatMessageRole
    tool_calls*: seq[ChatCompletionMessageToolCall]
    content*: ChatCompletionAssistantContent

  OpenAIChatCompletionChoice* = object
    index*: int
    message*: ChatCompletionAssistantMessage
    finish_reason*: FinishReason

  UsageInfo* = object
    prompt_tokens*: int
    completion_tokens*: int
    total_tokens*: int

  OpenAIChatCompletionOut* = object
    id*: string
    model*: string
    choices*: seq[OpenAIChatCompletionChoice]
    usage*: UsageInfo

  # Input schema (trimmed common fields)
  ChatCompletionInputContentKind* = enum
    text, parts

  ChatCompletionContentPartType* = enum
    text, image_url, input_audio

  ImageUrl* = object
    url*: string
    detail*: ImageDetail

  InputAudio* = object
    data*: string
    format*: InputAudioFormat

  ChatCompletionContentPart* = object
    case `type`*: ChatCompletionContentPartType
    of text:
      text*: string
    of image_url:
      image_url*: ImageUrl
    of input_audio:
      input_audio*: InputAudio

  ChatCompletionMessageContent* = object
    case kind*: ChatCompletionInputContentKind
    of text:
      text*: string
    of parts:
      parts*: seq[ChatCompletionContentPart]

  FunctionDefinition* = object
    name*: string
    description*: string
    parameters*: string

  ChatTool* = object
    `type`*: ChatToolType
    function*: FunctionDefinition

  ResponseFormatJsonSchema* = object
    name*: string
    schema*: string
    strict*: bool

  ResponseFormat* = object
    `type`*: ResponseFormatType
    json_schema*: ResponseFormatJsonSchema

  ChatMessage* = object
    role*: ChatMessageRole
    content*: ChatCompletionMessageContent
    name*: string
    tool_call_id*: string

  OpenAIChatCompletionsIn* = object
    model*: string
    messages*: seq[ChatMessage]
    stream*: bool
    temperature*: float
    max_tokens*: int
    tools*: seq[ChatTool]
    tool_choice*: ToolChoice
    response_format*: ResponseFormat

const
  EmptyFunctionParametersSchema* = """{"type":"object","properties":{}}"""

proc readJson*(dst: var ChatCompletionAssistantContent; p: var JsonParser) =
  if p.tok == tkString:
    dst = ChatCompletionAssistantContent(kind: text)
    readJson(dst.text, p)
  elif p.tok == tkBracketLe:
    dst = ChatCompletionAssistantContent(kind: parts)
    readJson(dst.parts, p)
  else:
    raiseParseErr(p, "string or array")

proc readJson*(dst: var ChatCompletionMessageContent; p: var JsonParser) =
  if p.tok == tkString:
    dst = ChatCompletionMessageContent(kind: text)
    readJson(dst.text, p)
  elif p.tok == tkBracketLe:
    dst = ChatCompletionMessageContent(kind: parts)
    readJson(dst.parts, p)
  else:
    raiseParseErr(p, "string or array")

proc writeJson*(s: Stream; x: ChatCompletionAssistantContent) =
  case x.kind
  of text:
    writeJson(s, x.text)
  of parts:
    writeJson(s, x.parts)

proc writeJson*(s: Stream; x: ChatCompletionMessageContent) =
  case x.kind
  of text:
    writeJson(s, x.text)
  of parts:
    writeJson(s, x.parts)

template writeJsonField(s: Stream; name: string; value: untyped) =
  if comma: streams.write(s, ",")
  else: comma = true
  escapeJson(s, name)
  streams.write(s, ":")
  writeJson(s, value)

template writeJsonRawField(s: Stream; name: string; value: string) =
  if comma: streams.write(s, ",")
  else: comma = true
  escapeJson(s, name)
  streams.write(s, ":")
  streams.write(s, value)

proc writeJson*(s: Stream; x: FunctionDefinition) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "name", x.name)
  if x.description.len > 0:
    writeJsonField(s, "description", x.description)
  if x.parameters.len > 0:
    writeJsonRawField(s, "parameters", x.parameters)
  else:
    writeJsonRawField(s, "parameters", EmptyFunctionParametersSchema)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseFormatJsonSchema) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "name", x.name)
  if x.schema.len > 0:
    writeJsonRawField(s, "schema", x.schema)
  else:
    writeJsonRawField(s, "schema", "{}")
  writeJsonField(s, "strict", x.strict)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseFormat) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "type", x.`type`)
  if x.`type` == ResponseFormatType.json_schema:
    writeJsonField(s, "json_schema", x.json_schema)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ChatMessage) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "role", x.role)
  writeJsonField(s, "content", x.content)
  if x.name.len > 0:
    writeJsonField(s, "name", x.name)
  if x.role == ChatMessageRole.tool and x.tool_call_id.len > 0:
    writeJsonField(s, "tool_call_id", x.tool_call_id)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: OpenAIChatCompletionsIn) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "model", x.model)
  writeJsonField(s, "messages", x.messages)
  if x.stream:
    writeJsonField(s, "stream", x.stream)
  if x.temperature != 1.0:
    writeJsonField(s, "temperature", x.temperature)
  if x.max_tokens != 0:
    writeJsonField(s, "max_tokens", x.max_tokens)
  if x.tools.len > 0:
    writeJsonField(s, "tools", x.tools)
    writeJsonField(s, "tool_choice", x.tool_choice)
  if x.response_format.`type` != ResponseFormatType.text:
    writeJsonField(s, "response_format", x.response_format)
  streams.write(s, "}")
