import jsonx
import jsonx/[parsejson, streams]

{.define: jsonxLenient.}

type
  ChatMessageRole* = enum
    system, user, assistant, tool

  ChatToolType* = enum
    function

  FinishReason* = enum
    stop, length, tool_calls, content_filter, malformed_function_call

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

  ChatTool* = object
    `type`*: ChatToolType
    function*: FunctionDefinition

  ResponseFormat* = object
    `type`*: ResponseFormatType

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
