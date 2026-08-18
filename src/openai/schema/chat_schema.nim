import std/options
export options
import jsonx
import jsonx/[parsejson, streams]
import ./[prompt_cache_schema, tolerant_enum]

export prompt_cache_schema

type
  ChatMessageRole* = enum
    system, developer, user, assistant, tool

  ChatToolType* = enum
    function

  ChatFinishReason* {.pure.} = enum
    unknown = ""
    stop, length, tool_calls, content_filter

  ChatImageDetail* = enum
    `auto`, low, high

  ChatAudioFormat* = enum
    wav, mp3

  ChatReasoningEffort* = enum
    unspecified = ""
    none
    minimal
    low
    medium
    high
    xhigh
    max

  ChatFormatType* = enum
    text, json_object, json_schema

  ChatAssistantContentKind* = enum
    none, text, parts

  ChatTextPart* = object
    `type`*: ChatInputPartType
    text*: string

  ChatFunctionCall* = object
    name*: string
    arguments*: string

  ChatToolCall* = object
    id*: string
    `type`*: ChatToolType
    function*: ChatFunctionCall

  ChatAssistantContent* = object
    case kind*: ChatAssistantContentKind
    of none:
      discard
    of text:
      text*: string
    of parts:
      parts*: seq[ChatTextPart]

  ChatAssistantMessage* = object
    role*: ChatMessageRole
    tool_calls*: seq[ChatToolCall]
    content*: ChatAssistantContent
    refusal*: Option[string]
    annotations*: seq[RawJson]

  ChatChoice* = object
    index*: int
    message*: ChatAssistantMessage
    finish_reason*: ChatFinishReason

  ChatPromptTokenDetails* = object
    cached_tokens*: int
    cache_write_tokens*: int
    audio_tokens*: int

  ChatOutputTokenDetails* = object
    reasoning_tokens*: int
    audio_tokens*: int
    accepted_prediction_tokens*: int
    rejected_prediction_tokens*: int

  ChatUsage* = object
    prompt_tokens*: int
    completion_tokens*: int
    total_tokens*: int
    prompt_tokens_details*: ChatPromptTokenDetails
    completion_tokens_details*: ChatOutputTokenDetails

  ChatResult* = object
    id*: string
    `object`*: string
    created*: int64
    model*: string
    choices*: seq[ChatChoice]
    usage*: Option[ChatUsage]
    service_tier*: string
    system_fingerprint*: Option[string]

  ChatInputContentKind* = enum
    text, parts

  ChatInputPartType* = enum
    text, image_url, input_audio

  ChatImageUrl* = object
    url*: string
    detail*: ChatImageDetail

  ChatInputAudio* = object
    data*: string
    format*: ChatAudioFormat

  ChatInputPart* = object
    case `type`*: ChatInputPartType
    of text:
      text*: string
    of image_url:
      image_url*: ChatImageUrl
    of input_audio:
      input_audio*: ChatInputAudio

  ChatInputContent* = object
    case kind*: ChatInputContentKind
    of text:
      text*: string
    of parts:
      parts*: seq[ChatInputPart]

  ChatFunctionDefinition* = object
    name*: string
    description*: string
    parameters*: RawJson
    strict*: bool

  ChatTool* = object
    `type`*: ChatToolType
    function*: ChatFunctionDefinition

  ChatNamedFunction* = object
    name*: string

  ChatToolChoice* = object
    `type`*: ChatToolType
    function*: ChatNamedFunction

  ChatJsonSchemaFormat* = object
    name*: string
    description*: string
    schema*: RawJson
    strict*: bool

  ChatFormat* = object
    `type`*: ChatFormatType
    json_schema*: ChatJsonSchemaFormat

  ChatMessage* = object
    role*: ChatMessageRole
    content*: ChatInputContent
    tool_calls*: seq[ChatToolCall]
    name*: string
    tool_call_id*: string

  ChatParams* = object
    model*: string
    messages*: seq[ChatMessage]
    stream*: bool
    temperature*: float = 1.0
    max_completion_tokens*: int
    reasoning_effort*: ChatReasoningEffort
    tools*: seq[ChatTool]
    tool_choice*: RawJson
    response_format*: ChatFormat
    parallel_tool_calls*: bool = true
    metadata*: RawJson
    prompt_cache_key*: string
    prompt_cache_options*: PromptCacheOptions
    safety_identifier*: string
    service_tier*: string
    store*: bool

const
  EmptyFunctionParametersSchema* = RawJson("""{"type":"object","properties":{}}""")
  ChatToolChoiceAuto* = RawJson("\"auto\"")
  ChatToolChoiceNone* = RawJson("\"none\"")
  ChatToolChoiceRequired* = RawJson("\"required\"")

proc readJson*(dst: var ChatFinishReason; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  readTolerantEnum(dst, p)

proc readJson*(dst: var ChatAssistantContent; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  case p.tok
  of tkNull:
    dst = ChatAssistantContent(kind: none)
    discard getTok(p)
  of tkString:
    dst = ChatAssistantContent(kind: text)
    readJson(dst.text, p, unknownFields)
  of tkBracketLe:
    dst = ChatAssistantContent(kind: parts)
    readJson(dst.parts, p, unknownFields)
  else:
    raiseParseErr(p, "string, array, or null")

proc readJson*(dst: var ChatInputContent; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  if p.tok == tkString:
    dst = ChatInputContent(kind: text)
    readJson(dst.text, p, unknownFields)
  elif p.tok == tkBracketLe:
    dst = ChatInputContent(kind: parts)
    readJson(dst.parts, p, unknownFields)
  else:
    raiseParseErr(p, "string or array")

proc writeJson*(s: Stream; x: ChatAssistantContent) =
  case x.kind
  of none:
    streams.write(s, "null")
  of text:
    writeJson(s, x.text)
  of parts:
    writeJson(s, x.parts)

proc writeJson*(s: Stream; x: ChatInputContent) =
  case x.kind
  of text:
    writeJson(s, x.text)
  of parts:
    writeJson(s, x.parts)

proc hasMessageContent(x: ChatMessage): bool =
  case x.content.kind
  of text:
    result = x.content.text.len > 0
  of parts:
    result = x.content.parts.len > 0

template writeJsonField(s: Stream; name: string; value: untyped) =
  if comma: streams.write(s, ",")
  else: comma = true
  escapeJson(s, name)
  streams.write(s, ":")
  writeJson(s, value)

proc writeJson*(s: Stream; x: ChatFunctionDefinition) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "name", x.name)
  if x.description.len > 0:
    writeJsonField(s, "description", x.description)
  if string(x.parameters).len > 0:
    writeJsonField(s, "parameters", x.parameters)
  else:
    writeJsonField(s, "parameters", EmptyFunctionParametersSchema)
  writeJsonField(s, "strict", x.strict)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ChatJsonSchemaFormat) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "name", x.name)
  if x.description.len > 0:
    writeJsonField(s, "description", x.description)
  if string(x.schema).len > 0:
    writeJsonField(s, "schema", x.schema)
  else:
    writeJsonField(s, "schema", RawJson("{}"))
  writeJsonField(s, "strict", x.strict)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ChatFormat) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "type", x.`type`)
  if x.`type` == ChatFormatType.json_schema:
    writeJsonField(s, "json_schema", x.json_schema)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ChatMessage) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "role", x.role)
  if x.tool_calls.len > 0:
    writeJsonField(s, "tool_calls", x.tool_calls)
  let omitAssistantContent = x.role == ChatMessageRole.assistant and
    x.tool_calls.len > 0 and not x.hasMessageContent()
  if not omitAssistantContent:
    writeJsonField(s, "content", x.content)
  if x.name.len > 0:
    writeJsonField(s, "name", x.name)
  if x.role == ChatMessageRole.tool and x.tool_call_id.len > 0:
    writeJsonField(s, "tool_call_id", x.tool_call_id)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ChatParams) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "model", x.model)
  writeJsonField(s, "messages", x.messages)
  if x.stream:
    writeJsonField(s, "stream", x.stream)
  if x.temperature != 1.0:
    writeJsonField(s, "temperature", x.temperature)
  if x.max_completion_tokens != 0:
    writeJsonField(s, "max_completion_tokens", x.max_completion_tokens)
  if x.reasoning_effort != ChatReasoningEffort.unspecified:
    writeJsonField(s, "reasoning_effort", x.reasoning_effort)
  if x.tools.len > 0:
    writeJsonField(s, "tools", x.tools)
  if string(x.tool_choice).len > 0:
    writeJsonField(s, "tool_choice", x.tool_choice)
  if x.response_format.`type` != ChatFormatType.text:
    writeJsonField(s, "response_format", x.response_format)
  if not x.parallel_tool_calls:
    writeJsonField(s, "parallel_tool_calls", x.parallel_tool_calls)
  if string(x.metadata).len > 0:
    writeJsonField(s, "metadata", x.metadata)
  if x.prompt_cache_key.len > 0:
    writeJsonField(s, "prompt_cache_key", x.prompt_cache_key)
  if x.prompt_cache_options.mode != PromptCacheMode.unspecified or
      x.prompt_cache_options.ttl != PromptCacheTtl.unspecified:
    writeJsonField(s, "prompt_cache_options", x.prompt_cache_options)
  if x.safety_identifier.len > 0:
    writeJsonField(s, "safety_identifier", x.safety_identifier)
  if x.service_tier.len > 0:
    writeJsonField(s, "service_tier", x.service_tier)
  if x.store:
    writeJsonField(s, "store", x.store)
  streams.write(s, "}")
