## JSON-mapped types for the OpenAI Responses API.
##
## Deprecated API fields are deliberately absent from this schema.

import std/options
export options
import jsonx
import jsonx/[parsejson, streams]
import ./[prompt_cache_schema, tolerant_enum]

export prompt_cache_schema

type
  ResponseInputKind* = enum
    text, items

  ResponseInput* = object
    case kind*: ResponseInputKind
    of text:
      text*: string
    of items:
      items*: seq[RawJson]

  ResponseRole* = enum
    system, developer, user, assistant

  ResponsePartType* = enum
    input_text, input_image, input_file

  ResponsePart* = object
    `type`*: ResponsePartType
    text*: string
    image_url*: string
    file_id*: string
    file_url*: string
    filename*: string
    file_data*: string
    detail*: string

  ResponseContentKind* = enum
    text, parts

  ResponseContent* = object
    case kind*: ResponseContentKind
    of text:
      text*: string
    of parts:
      parts*: seq[ResponsePart]

  ResponseMessage* = object
    role*: ResponseRole
    content*: ResponseContent

  ResponseFunctionOutputType* = enum
    function_call_output

  ResponseFunctionOutput* = object
    `type`*: ResponseFunctionOutputType
    call_id*: string
    output*: ResponseContent

  ResponseToolType* = enum
    function

  ResponseFunctionTool* = object
    `type`*: ResponseToolType
    name*: string
    description*: string
    parameters*: RawJson
    strict*: bool

  ResponseToolChoice* = object
    `type`*: ResponseToolType
    name*: string

  ResponseFormatType* = enum
    text, json_object, json_schema

  ResponseFormat* = object
    `type`*: ResponseFormatType
    name*: string
    description*: string
    schema*: RawJson
    strict*: bool

  ResponseTextConfig* = object
    format*: ResponseFormat
    verbosity*: string

  ResponseReasoningEffort* = enum
    unspecified = ""
    none
    low
    medium
    high
    xhigh
    max

  ResponseReasoning* = object
    effort*: ResponseReasoningEffort
    summary*: string
    mode*: string
    context*: string

  ResponseParams* = object
    model*: string
    input*: ResponseInput
    background*: bool
    context_management*: seq[RawJson]
    conversation*: string
    `include`*: seq[string]
    instructions*: string
    max_output_tokens*: int
    max_tool_calls*: int
    metadata*: RawJson
    moderation*: RawJson
    parallel_tool_calls*: bool = true
    previous_response_id*: string
    prompt*: RawJson
    prompt_cache_key*: string
    prompt_cache_options*: PromptCacheOptions
    reasoning*: ResponseReasoning
    safety_identifier*: string
    service_tier*: string
    store*: bool = true
    stream*: bool
    stream_options*: RawJson
    temperature*: float = 1.0
    text*: ResponseTextConfig
    tool_choice*: RawJson
    tools*: seq[RawJson]
    top_logprobs*: int
    top_p*: float = 1.0

  ResponseError* = object
    code*: string
    message*: string

  ResponseIncomplete* = object
    reason*: string

  ResponseInputTokenDetails* = object
    cached_tokens*: int
    cache_write_tokens*: int

  ResponseOutputTokenDetails* = object
    reasoning_tokens*: int

  ResponseUsage* = object
    input_tokens*: int
    input_tokens_details*: ResponseInputTokenDetails
    output_tokens*: int
    output_tokens_details*: ResponseOutputTokenDetails
    total_tokens*: int

  ResponseOutputPartType* {.pure.} = enum
    unknown = ""
    output_text
    refusal
    reasoning_text

  ResponseOutputPart* = object
    `type`*: ResponseOutputPartType
    text*: string
    refusal*: string
    annotations*: seq[RawJson]
    logprobs*: seq[RawJson]

  ResponseOutputKind* {.pure.} = enum
    unknown = ""
    message
    function_call
    reasoning
    file_search_call
    computer_call
    web_search_call
    image_generation_call
    code_interpreter_call
    local_shell_call
    mcp_call
    mcp_list_tools
    mcp_approval_request
    custom_tool_call
    apply_patch_call
    shell_call
    compaction

  ResponseReasoningSummaryPartType* {.pure.} = enum
    unknown = ""
    summary_text

  ResponseReasoningSummaryPart* = object
    `type`*: ResponseReasoningSummaryPartType
    text*: string

  ResponseOutputMessage* = object
    role*: string
    content*: seq[ResponseOutputPart]

  ResponseOutputFunctionCall* = object
    call_id*: string
    name*: string
    arguments*: string

  ResponseReasoningOutput* = object
    summary*: seq[ResponseReasoningSummaryPart]
    content*: seq[ResponseOutputPart]
    encrypted_content*: string

  ResponseOutputShape = enum
    outputMessage
    outputFunctionCall
    outputReasoning
    outputOpaque

  ResponseOutput* = object
    id*: string
    status*: string
    `type`*: ResponseOutputKind
    case shape: ResponseOutputShape
    of outputMessage:
      message*: ResponseOutputMessage
    of outputFunctionCall:
      functionCall*: ResponseOutputFunctionCall
    of outputReasoning:
      reasoning*: ResponseReasoningOutput
    of outputOpaque:
      extraFields*: RawJson

  ResponseStatus* {.pure.} = enum
    unknown = ""
    completed
    in_progress
    failed
    cancelled
    queued
    incomplete

  ResponseResult* = object
    id*: string
    `object`*: string
    created_at*: float
    completed_at*: Option[int64]
    background*: bool
    status*: ResponseStatus
    error*: Option[ResponseError]
    incomplete_details*: Option[ResponseIncomplete]
    model*: string
    output*: seq[ResponseOutput]
    previous_response_id*: string
    service_tier*: string
    usage*: Option[ResponseUsage]
    metadata*: RawJson
    reasoning*: RawJson

const
  EmptyResponseObjectSchema* = RawJson("""{"type":"object","properties":{}}""")
  ResponseToolChoiceAuto* = RawJson("\"auto\"")
  ResponseToolChoiceNone* = RawJson("\"none\"")
  ResponseToolChoiceRequired* = RawJson("\"required\"")

template writeJsonField(s: Stream; name: string; value: untyped) =
  if comma: streams.write(s, ",")
  else: comma = true
  escapeJson(s, name)
  streams.write(s, ":")
  writeJson(s, value)

proc writeJson*(s: Stream; x: ResponseInput) =
  case x.kind
  of ResponseInputKind.text:
    writeJson(s, x.text)
  of ResponseInputKind.items:
    writeJson(s, x.items)

proc readJson*(dst: var ResponseOutputPartType; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  readTolerantEnum(dst, p)

proc readJson*(dst: var ResponseOutputKind; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  readTolerantEnum(dst, p)

proc readJson*(dst: var ResponseReasoningSummaryPartType; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  readTolerantEnum(dst, p)

proc appendRawField(dst: var string; name: string; p: var JsonParser) =
  if dst.len == 0:
    dst.add('{')
  else:
    dst.add(',')
  escapeJson(name, dst)
  dst.add(':')
  appendRawJson(dst, p)

proc finishRawObject(dst: var string): RawJson {.inline.} =
  if dst.len > 0:
    dst.add('}')
  result = RawJson(move(dst))

proc makeTypedResponseOutput(kind: ResponseOutputKind; id, status, role: sink string;
    content: sink seq[ResponseOutputPart]; callId, name, arguments: sink string;
    summary: sink seq[ResponseReasoningSummaryPart];
    encryptedContent: sink string): ResponseOutput =
  case kind
  of message:
    result = ResponseOutput(
      id: id,
      status: status,
      `type`: kind,
      shape: outputMessage,
      message: ResponseOutputMessage(role: role, content: content)
    )
  of function_call:
    result = ResponseOutput(
      id: id,
      status: status,
      `type`: kind,
      shape: outputFunctionCall,
      functionCall: ResponseOutputFunctionCall(
        call_id: callId,
        name: name,
        arguments: arguments
      )
    )
  of reasoning:
    result = ResponseOutput(
      id: id,
      status: status,
      `type`: kind,
      shape: outputReasoning,
      reasoning: ResponseReasoningOutput(
        summary: summary,
        content: content,
        encrypted_content: encryptedContent
      )
    )
  else:
    discard

proc readJson*(dst: var ResponseOutput; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  var id, status, role, callId, name, arguments, encryptedContent: string
  var kind: ResponseOutputKind = unknown
  var content: seq[ResponseOutputPart] = @[]
  var summary: seq[ResponseReasoningSummaryPart] = @[]
  var extra = ""

  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    let fieldName = p.a
    discard getTok(p)
    eat(p, tkColon)
    case fieldName
    of "id":
      readJson(id, p, unknownFields)
    of "status":
      readJson(status, p, unknownFields)
    of "type":
      readJson(kind, p, unknownFields)
    of "role":
      readJson(role, p, unknownFields)
    of "content":
      readJson(content, p, unknownFields)
    of "call_id":
      readJson(callId, p, unknownFields)
    of "name":
      readJson(name, p, unknownFields)
    of "arguments":
      readJson(arguments, p, unknownFields)
    of "summary":
      readJson(summary, p, unknownFields)
    of "encrypted_content":
      readJson(encryptedContent, p, unknownFields)
    else:
      appendRawField(extra, fieldName, p)

    if p.tok == tkComma:
      discard getTok(p)
    elif p.tok != tkCurlyRi:
      raiseParseErr(p, "',' or '}'")
  eat(p, tkCurlyRi)

  case kind
  of message, function_call, reasoning:
    if unknownFields == ufReject and extra.len > 0:
      raiseParseErr(p, "known field for this typed output item")
    dst = makeTypedResponseOutput(kind, id, status, role, content, callId,
      name, arguments, summary, encryptedContent)
  else:
    dst = ResponseOutput(
      id: id,
      status: status,
      `type`: kind,
      shape: outputOpaque,
      extraFields: finishRawObject(extra)
    )

proc readJson*(dst: var ResponseStatus; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  readTolerantEnum(dst, p)

proc readJson*(dst: var ResponseContent; p: var JsonParser;
    unknownFields: UnknownFieldPolicy) =
  if p.tok == tkString:
    dst = ResponseContent(kind: ResponseContentKind.text)
    readJson(dst.text, p, unknownFields)
  elif p.tok == tkBracketLe:
    dst = ResponseContent(kind: ResponseContentKind.parts)
    readJson(dst.parts, p, unknownFields)
  else:
    raiseParseErr(p, "string or array")

proc writeJson*(s: Stream; x: ResponsePart) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "type", x.`type`)
  case x.`type`
  of ResponsePartType.input_text:
    writeJsonField(s, "text", x.text)
  of ResponsePartType.input_image:
    if x.image_url.len > 0:
      writeJsonField(s, "image_url", x.image_url)
    else:
      writeJsonField(s, "file_id", x.file_id)
    if x.detail.len > 0:
      writeJsonField(s, "detail", x.detail)
  of ResponsePartType.input_file:
    if x.file_id.len > 0:
      writeJsonField(s, "file_id", x.file_id)
    elif x.file_url.len > 0:
      writeJsonField(s, "file_url", x.file_url)
    else:
      writeJsonField(s, "file_data", x.file_data)
      if x.filename.len > 0:
        writeJsonField(s, "filename", x.filename)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseContent) =
  case x.kind
  of ResponseContentKind.text:
    writeJson(s, x.text)
  of ResponseContentKind.parts:
    writeJson(s, x.parts)

proc writeJson*(s: Stream; x: ResponseFunctionTool) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "type", x.`type`)
  writeJsonField(s, "name", x.name)
  if x.description.len > 0:
    writeJsonField(s, "description", x.description)
  if string(x.parameters).len > 0:
    writeJsonField(s, "parameters", x.parameters)
  else:
    writeJsonField(s, "parameters", EmptyResponseObjectSchema)
  writeJsonField(s, "strict", x.strict)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseFormat) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "type", x.`type`)
  if x.`type` == ResponseFormatType.json_schema:
    writeJsonField(s, "name", x.name)
    if x.description.len > 0:
      writeJsonField(s, "description", x.description)
    if string(x.schema).len > 0:
      writeJsonField(s, "schema", x.schema)
    else:
      writeJsonField(s, "schema", RawJson("{}"))
    writeJsonField(s, "strict", x.strict)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseTextConfig) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "format", x.format)
  if x.verbosity.len > 0:
    writeJsonField(s, "verbosity", x.verbosity)
  streams.write(s, "}")

proc writeJson*(s: Stream; x: ResponseReasoning) =
  var comma = false
  streams.write(s, "{")
  if x.effort != ResponseReasoningEffort.unspecified:
    writeJsonField(s, "effort", x.effort)
  if x.summary.len > 0:
    writeJsonField(s, "summary", x.summary)
  if x.mode.len > 0:
    writeJsonField(s, "mode", x.mode)
  if x.context.len > 0:
    writeJsonField(s, "context", x.context)
  streams.write(s, "}")

proc hasPromptCacheOptions(x: PromptCacheOptions): bool {.inline.} =
  x.mode != PromptCacheMode.unspecified or
    x.ttl != PromptCacheTtl.unspecified

proc hasReasoning(x: ResponseReasoning): bool {.inline.} =
  x.effort != ResponseReasoningEffort.unspecified or x.summary.len > 0 or
    x.mode.len > 0 or x.context.len > 0

proc hasTextConfig(x: ResponseTextConfig): bool {.inline.} =
  x.format.`type` != ResponseFormatType.text or x.verbosity.len > 0

proc writeJson*(s: Stream; x: ResponseParams) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "model", x.model)
  writeJsonField(s, "input", x.input)
  if x.background: writeJsonField(s, "background", x.background)
  if x.context_management.len > 0:
    writeJsonField(s, "context_management", x.context_management)
  if x.conversation.len > 0: writeJsonField(s, "conversation", x.conversation)
  if x.`include`.len > 0: writeJsonField(s, "include", x.`include`)
  if x.instructions.len > 0: writeJsonField(s, "instructions", x.instructions)
  if x.max_output_tokens > 0: writeJsonField(s, "max_output_tokens", x.max_output_tokens)
  if x.max_tool_calls > 0: writeJsonField(s, "max_tool_calls", x.max_tool_calls)
  if string(x.metadata).len > 0: writeJsonField(s, "metadata", x.metadata)
  if string(x.moderation).len > 0: writeJsonField(s, "moderation", x.moderation)
  if not x.parallel_tool_calls:
    writeJsonField(s, "parallel_tool_calls", x.parallel_tool_calls)
  if x.previous_response_id.len > 0:
    writeJsonField(s, "previous_response_id", x.previous_response_id)
  if string(x.prompt).len > 0: writeJsonField(s, "prompt", x.prompt)
  if x.prompt_cache_key.len > 0: writeJsonField(s, "prompt_cache_key", x.prompt_cache_key)
  if x.prompt_cache_options.hasPromptCacheOptions():
    writeJsonField(s, "prompt_cache_options", x.prompt_cache_options)
  if x.reasoning.hasReasoning(): writeJsonField(s, "reasoning", x.reasoning)
  if x.safety_identifier.len > 0:
    writeJsonField(s, "safety_identifier", x.safety_identifier)
  if x.service_tier.len > 0: writeJsonField(s, "service_tier", x.service_tier)
  if not x.store: writeJsonField(s, "store", x.store)
  if x.stream: writeJsonField(s, "stream", x.stream)
  if string(x.stream_options).len > 0:
    writeJsonField(s, "stream_options", x.stream_options)
  if x.temperature != 1.0: writeJsonField(s, "temperature", x.temperature)
  if x.text.hasTextConfig(): writeJsonField(s, "text", x.text)
  if string(x.tool_choice).len > 0: writeJsonField(s, "tool_choice", x.tool_choice)
  if x.tools.len > 0: writeJsonField(s, "tools", x.tools)
  if x.top_logprobs > 0: writeJsonField(s, "top_logprobs", x.top_logprobs)
  if x.top_p != 1.0: writeJsonField(s, "top_p", x.top_p)
  streams.write(s, "}")
