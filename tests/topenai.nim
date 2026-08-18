import relay
import jsonx
import jsonx/parsejson
import openai/chat
import std/strutils

const GoodResponse = """{
  "id": "cmpl_1",
  "created": 1711652795,
  "model": "gpt-4.1-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": [],
        "content": "Hello",
        "future_message_field": true
      },
      "finish_reason": "stop",
      "future_choice_field": []
    }
  ],
  "usage": {
    "prompt_tokens": 1,
    "completion_tokens": 2,
    "total_tokens": 3,
    "future_usage_field": {}
  },
  "future_response_field": "ignored"
}"""

const PartsResponse = """{
  "id": "cmpl_parts",
  "model": "gpt-4.1-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": [
          {
            "id": "call_1",
            "type": "function",
            "function": {
              "name": "lookup",
              "arguments": "{\"q\":\"nim\"}",
              "future_function_field": 1
            },
            "future_call_field": false
          }
        ],
        "content": [
          {"type":"text","text":"first"},
          {"type":"text","text":"second"}
        ]
      },
      "finish_reason": "tool_calls"
    }
  ],
  "usage": {
    "prompt_tokens": 9,
    "completion_tokens": 5,
    "total_tokens": 14
  }
}"""

const JsonTextResponse = """{
  "id": "cmpl_json",
  "model": "gpt-4.1-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": [],
        "content": "{\"city\":\"Seattle\",\"temperatureC\":9.0,\"condition\":\"light rain\",\"advice\":\"Wear a jacket.\"}"
      },
      "finish_reason": "stop"
    },
    {
      "index": 1,
      "message": {
        "role": "assistant",
        "tool_calls": [],
        "content": "not json"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 15,
    "total_tokens": 27
  }
}"""

const ToolCallResponse = """{
  "id": "chatcmpl_tc",
  "object": "chat.completion",
  "created": 1786007317,
  "model": "gpt-5.6-luna",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_1",
            "type": "function",
            "function": {
              "name": "lookup",
              "arguments": "{\"q\":\"nim\"}"
            }
          }
        ],
        "refusal": null,
        "annotations": []
      },
      "finish_reason": "tool_calls"
    }
  ],
  "usage": {
    "prompt_tokens": 46,
    "completion_tokens": 14,
    "total_tokens": 60,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "cache_write_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 10,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0,
      "future_output_tokens_field": 0
    },
    "future_usage_field": null
  },
  "service_tier": "default",
  "system_fingerprint": null
}"""

type
  ParsedWeatherAnswer = object
    city: string
    temperatureC: float
    condition: string
    advice: string

  ParsedToolArgs = object
    q: string

template expectValueError(body: untyped) =
  var raised = false
  try:
    discard body
  except ValueError:
    raised = true
  doAssert raised

proc sampleParams(streamValue = false): ChatParams =
  chatCreate(
    model = "gpt-4.1-mini",
    stream = streamValue,
    temperature = 0.2,
    maxCompletionTokens = 64,
    responseFormat = formatText,
    messages = @[
      userMessageText("ping")
    ]
  )

proc sampleConfig(apiKey = "sk-test"): OpenAIConfig =
  OpenAIConfig(
    url: OpenAIBaseUrl,
    apiKey: apiKey
  )

proc testChatRequest() =
  let cfg = sampleConfig(apiKey = "new-token")
  var headers = emptyHttpHeaders()
  headers["Authorization"] = "Bearer old-token"
  headers["Content-Type"] = "text/plain"
  headers["X-Trace-Id"] = "trace-1"

  let req = chatRequest(
    cfg,
    sampleParams(),
    requestId = 42,
    timeoutMs = 7_000,
    headers = move headers
  )

  doAssert req.verb == hvPost
  doAssert req.url == cfg.url & "/chat/completions"
  doAssert req.requestId == 42
  doAssert req.timeoutMs == 7_000
  doAssert req.headers["Authorization"] == "Bearer new-token"
  doAssert req.headers["Content-Type"] == "application/json"
  doAssert req.headers["X-Trace-Id"] == "trace-1"

  let payload = fromJson(req.body, ChatParams)
  doAssert payload.model == "gpt-4.1-mini"
  doAssert payload.messages.len == 1
  doAssert payload.messages[0].content.kind == ChatInputContentKind.text
  doAssert payload.messages[0].content.text == "ping"

proc testInputConstructorsCoverage() =
  let pText = partText("plain")
  doAssert pText.`type` == ChatInputPartType.text
  doAssert pText.text == "plain"

  let pImg = partImageUrl("https://example.com/a.png", detail = ChatImageDetail.high)
  doAssert pImg.`type` == ChatInputPartType.image_url
  doAssert pImg.image_url.url == "https://example.com/a.png"
  doAssert pImg.image_url.detail == ChatImageDetail.high

  let pAudio = partInputAudio("base64audio", ChatAudioFormat.mp3)
  doAssert pAudio.`type` == ChatInputPartType.input_audio
  doAssert pAudio.input_audio.data == "base64audio"
  doAssert pAudio.input_audio.format == ChatAudioFormat.mp3

  let cText = contentText("hello")
  doAssert cText.kind == ChatInputContentKind.text
  doAssert cText.text == "hello"

  let cParts = contentParts(@[pText, pImg, pAudio])
  doAssert cParts.kind == ChatInputContentKind.parts
  doAssert cParts.parts.len == 3
  doAssert cParts.parts[1].`type` == ChatInputPartType.image_url

  let mSystem = systemMessageText("rules", name = "sys")
  doAssert mSystem.role == ChatMessageRole.system
  doAssert mSystem.content.kind == ChatInputContentKind.text
  doAssert mSystem.content.text == "rules"
  doAssert mSystem.name == "sys"

  let mDeveloper = developerMessageText("developer rules")
  doAssert mDeveloper.role == ChatMessageRole.developer
  doAssert mDeveloper.content.text == "developer rules"

  let mUserText = userMessageText("ask")
  doAssert mUserText.role == ChatMessageRole.user
  doAssert mUserText.content.kind == ChatInputContentKind.text
  doAssert mUserText.content.text == "ask"

  let mUserParts = userMessageParts(@[pText, pImg], name = "u")
  doAssert mUserParts.role == ChatMessageRole.user
  doAssert mUserParts.content.kind == ChatInputContentKind.parts
  doAssert mUserParts.content.parts.len == 2
  doAssert mUserParts.name == "u"

  let mAssistant = assistantMessageText("draft")
  doAssert mAssistant.role == ChatMessageRole.assistant
  doAssert mAssistant.content.kind == ChatInputContentKind.text
  doAssert mAssistant.content.text == "draft"

  let toolCall = ChatToolCall(
    id: "call_1",
    `type`: ChatToolType.function,
    function: ChatFunctionCall(
      name: "lookup",
      arguments: "{\"q\":\"nim\"}"
    )
  )
  let mAssistantCalls = assistantMessageToolCalls(@[toolCall])
  doAssert mAssistantCalls.role == ChatMessageRole.assistant
  doAssert mAssistantCalls.tool_calls.len == 1
  doAssert mAssistantCalls.tool_calls[0].id == "call_1"

  let mTool = toolMessageText("result-json", "call_99", name = "tool-name")
  doAssert mTool.role == ChatMessageRole.tool
  doAssert mTool.content.kind == ChatInputContentKind.text
  doAssert mTool.content.text == "result-json"
  doAssert mTool.tool_call_id == "call_99"
  doAssert mTool.name == "tool-name"

  let mToolJson = toolMessageJson((city: "Berlin", celsius: 3.5), "call_100",
    name = "weather")
  doAssert mToolJson.role == ChatMessageRole.tool
  doAssert mToolJson.content.kind == ChatInputContentKind.text
  doAssert mToolJson.content.text == """{"city":"Berlin","celsius":3.5}"""
  doAssert mToolJson.tool_call_id == "call_100"
  doAssert mToolJson.name == "weather"

  let tool = functionTool("lookup", "search docs")
  doAssert tool.`type` == ChatToolType.function
  doAssert tool.function.name == "lookup"
  doAssert tool.function.description == "search docs"
  doAssert string(tool.function.parameters) == string(EmptyFunctionParametersSchema)
  doAssert tool.function.strict

  type
    ToolSchema = object
      `type`: string

  let typedTool = functionTool("typed", ToolSchema(`type`: "object"))
  doAssert string(typedTool.function.parameters) == """{"type":"object"}"""

  doAssert formatText.`type` == ChatFormatType.text
  doAssert formatJsonObject.`type` == ChatFormatType.json_object
  let jsonSchemaFormat = formatJsonSchema(
    "output",
    RawJson("""{"type":"object"}"""),
    description = "Output data"
  )
  doAssert jsonSchemaFormat.`type` == ChatFormatType.json_schema
  doAssert jsonSchemaFormat.json_schema.name == "output"
  doAssert jsonSchemaFormat.json_schema.description == "Output data"
  doAssert string(jsonSchemaFormat.json_schema.schema) == """{"type":"object"}"""
  doAssert jsonSchemaFormat.json_schema.strict

proc testChatCreateParamsBuilder() =
  let request = chatCreate(
    model = "gpt-4.1",
    messages = @[systemMessageText("sys"), userMessageParts(@[partText("what?")])],
    stream = true,
    temperature = 0.75,
    maxCompletionTokens = 321,
    tools = @[functionTool("calc", "math")],
    toolChoice = ChatToolChoiceRequired,
    responseFormat = formatJsonObject
  )

  doAssert request.model == "gpt-4.1"
  doAssert request.messages.len == 2
  doAssert request.messages[1].content.kind == ChatInputContentKind.parts
  doAssert request.stream
  doAssert request.temperature == 0.75
  doAssert request.max_completion_tokens == 321
  doAssert request.tools.len == 1
  doAssert request.tools[0].function.name == "calc"
  doAssert string(request.tool_choice) == string(ChatToolChoiceRequired)
  doAssert request.response_format.`type` == ChatFormatType.json_object

proc testChatCreateMaxCompletionTokensSerialization() =
  let defaultRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")]
  )
  let defaultJson = toJson(defaultRequest)
  doAssert not defaultJson.contains("\"max_completion_tokens\":")
  doAssert not defaultJson.contains("\"stream\":")
  doAssert not defaultJson.contains("\"temperature\":")
  doAssert not defaultJson.contains("\"tools\":")
  doAssert not defaultJson.contains("\"tool_choice\":")
  doAssert not defaultJson.contains("\"response_format\":")
  doAssert not defaultJson.contains("\"name\":")
  doAssert not defaultJson.contains("\"tool_call_id\":")

  let explicitRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    maxCompletionTokens = 64
  )
  let explicitJson = toJson(explicitRequest)
  doAssert explicitJson.contains("\"max_completion_tokens\":64")

  let completionRequest = chatCreate(
    model = "gpt-5.6-luna",
    messages = @[userMessageText("ping")],
    maxCompletionTokens = 128
  )
  doAssert toJson(completionRequest).contains("\"max_completion_tokens\":128")

  let noReasoningRequest = chatCreate(
    model = "gpt-5.6-luna",
    messages = @[userMessageText("ping")],
    reasoningEffort = ChatReasoningEffort.none
  )
  doAssert toJson(noReasoningRequest).contains(
    "\"reasoning_effort\":\"none\"",
  )

  let maxReasoningRequest = chatCreate(
    model = "gpt-5.6-sol",
    messages = @[userMessageText("ping")],
    reasoningEffort = ChatReasoningEffort.max
  )
  doAssert toJson(maxReasoningRequest).contains(
    "\"reasoning_effort\":\"max\""
  )

proc testChatCreateSerializationFieldInclusionRules() =
  let request = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      userMessageText("ping", name = "alice"),
      toolMessageText("result", "call_1")
    ],
    stream = true,
    temperature = 0.2,
    maxCompletionTokens = 64,
    tools = @[
      functionTool("lookup", "search docs"),
      functionTool("extract")
    ],
    toolChoice = ChatToolChoiceRequired,
    responseFormat = formatJsonObject
  )
  let json = toJson(request)
  doAssert json.contains("\"stream\":true")
  doAssert json.contains("\"temperature\":0.2")
  doAssert json.contains("\"tool_choice\":\"required\"")
  doAssert json.contains("\"response_format\":{\"type\":\"json_object\"}")
  doAssert json.contains("\"name\":\"alice\"")
  doAssert json.contains("\"tool_call_id\":\"call_1\"")
  doAssert json.contains(
    """"name":"lookup","description":"search docs","parameters":""" &
      """{"type":"object","properties":{}},"strict":true"""
  )
  doAssert not json.contains("\"name\":\"extract\",\"description\":")

  let noToolsRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    toolChoice = ChatToolChoiceRequired
  )
  let noToolsJson = toJson(noToolsRequest)
  doAssert not noToolsJson.contains("\"tools\":")
  doAssert noToolsJson.contains("\"tool_choice\":\"required\"")

  let toolsDefaultChoiceRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    tools = @[functionTool("lookup")]
  )
  let toolsDefaultChoiceJson = toJson(toolsDefaultChoiceRequest)
  doAssert toolsDefaultChoiceJson.contains("\"tools\":[")
  doAssert not toolsDefaultChoiceJson.contains("\"tool_choice\":")

  let toolsAutoChoiceRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    tools = @[functionTool("lookup")],
    toolChoice = ChatToolChoiceAuto
  )
  let toolsAutoChoiceJson = toJson(toolsAutoChoiceRequest)
  doAssert toolsAutoChoiceJson.contains("\"tools\":[")
  doAssert toolsAutoChoiceJson.contains("\"tool_choice\":\"auto\"")

  let namedChoice = toolChoiceFunction("lookup")
  doAssert namedChoice.`type` == ChatToolType.function
  doAssert namedChoice.function.name == "lookup"
  doAssert toJson(namedChoice) ==
    """{"type":"function","function":{"name":"lookup"}}"""

  let decodedChoice = fromJson(
    """{"type":"function","function":{"name":"decoded"},"future":true}""",
    ChatToolChoice
  )
  doAssert decodedChoice.function.name == "decoded"
  doAssertRaises JsonParsingError:
    discard fromJson(
      """{"type":"function","function":{"name":"decoded"},"future":true}""",
      ChatToolChoice,
      unknownFields = ufReject
    )

proc testAssistantToolCallMessageSerialization() =
  let toolCall = ChatToolCall(
    id: "call_1",
    `type`: ChatToolType.function,
    function: ChatFunctionCall(
      name: "lookup",
      arguments: "{\"q\":\"nim\"}"
    )
  )

  let toolCallOnlyRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      assistantMessageToolCalls(@[toolCall])
    ],
    tools = @[functionTool("lookup")]
  )
  let toolCallOnlyJson = toJson(toolCallOnlyRequest)
  doAssert toolCallOnlyJson.contains("\"tool_calls\":[{")
  doAssert not toolCallOnlyJson.contains("\"content\":")

  let toolCallWithContentRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      ChatMessage(
        role: ChatMessageRole.assistant,
        content: contentText("Looking this up"),
        tool_calls: @[toolCall]
      )
    ],
    tools = @[functionTool("lookup")]
  )
  let toolCallWithContentJson = toJson(toolCallWithContentRequest)
  doAssert toolCallWithContentJson.contains("\"tool_calls\":[{")
  doAssert toolCallWithContentJson.contains("\"content\":\"Looking this up\"")

proc testSerializationRoundTripForBuiltRequest() =
  let request = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      userMessageParts(@[
        partText("describe"),
        partImageUrl("https://example.com/1.jpg", detail = ChatImageDetail.low),
        partInputAudio("ZGF0YQ==", ChatAudioFormat.wav)
      ])
    ],
    maxCompletionTokens = 128,
    responseFormat = formatText
  )
  let serialized = toJson(request)
  let parsed = fromJson(serialized, ChatParams)
  doAssert parsed.model == request.model
  doAssert parsed.messages.len == 1
  doAssert parsed.messages[0].content.kind == ChatInputContentKind.parts
  doAssert parsed.messages[0].content.parts.len == 3
  doAssert parsed.messages[0].content.parts[1].image_url.detail == ChatImageDetail.low

proc testStreamingFlagPassesThrough() =
  let cfg = sampleConfig()
  let req = chatRequest(cfg, sampleParams(streamValue = true))
  let payload = fromJson(req.body, ChatParams)
  doAssert payload.stream

proc testChatAdd() =
  let cfg = sampleConfig(apiKey = "batch-token")
  var batch: RequestBatch
  chatAdd(batch, cfg, sampleParams(), requestId = 11, timeoutMs = 1_500)
  chatAdd(batch, cfg, sampleParams(), requestId = 12)

  doAssert batch.len == 2
  doAssert batch[0].verb == hvPost
  doAssert batch[0].url == cfg.url & "/chat/completions"
  doAssert batch[0].requestId == 11
  doAssert batch[0].timeoutMs == 1_500
  doAssert batch[0].headers["Authorization"] == "Bearer batch-token"
  doAssert batch[0].headers["Content-Type"] == "application/json"
  doAssert batch[1].requestId == 12

proc testChatParse() =
  var decoded: ChatResult
  doAssert chatParse(GoodResponse, decoded)
  doAssert decoded.id == "cmpl_1"
  doAssert decoded.model == "gpt-4.1-mini"
  doAssert decoded.choices.len == 1
  doAssert decoded.choices[0].message.content.kind == ChatAssistantContentKind.text
  doAssert decoded.choices[0].message.content.text == "Hello"
  doAssert decoded.usage.isSome
  doAssert decoded.usage.get.total_tokens == 3

  var futureReason: ChatResult
  doAssert chatParse(GoodResponse.replace("\"stop\"", "\"future_reason\""), futureReason)
  doAssert futureReason.choices[0].finish_reason == ChatFinishReason.unknown

  var numericReason: ChatResult
  doAssert not chatParse(GoodResponse.replace("\"stop\"", "0"), numericReason)

  var bad: ChatResult
  doAssert not chatParse("{", bad)

proc testResponseGettersWithTextContent() =
  var parsed: ChatResult
  doAssert chatParse(GoodResponse, parsed)
  doAssert parsed.id == "cmpl_1"
  doAssert createdAt(parsed) == 1711652795
  doAssert parsed.model == "gpt-4.1-mini"
  doAssert parsed.choices.len == 1
  doAssert finish(parsed) == ChatFinishReason.stop
  doAssert firstText(parsed) == "Hello"
  doAssert outputText(parsed) == "Hello"
  doAssert hasUsage(parsed)
  doAssert usageOf(parsed).total_tokens == 3
  doAssert inputTokens(parsed) == 1
  doAssert outputTokens(parsed) == 2
  doAssert cachedInputTokens(parsed) == 0
  doAssert cacheWriteTokens(parsed) == 0
  doAssert reasoningTokens(parsed) == 0
  doAssert totalTokens(parsed) == 3
  doAssert functionCalls(parsed).len == 0
  doAssert not hasFunctionCalls(parsed)
  expectValueError(firstCallId(parsed))
  expectValueError(firstCallName(parsed))
  expectValueError(firstCallArgs(parsed))

proc testResponseGettersWithPartsAndToolCalls() =
  var parsed: ChatResult
  doAssert chatParse(PartsResponse, parsed)
  doAssert finish(parsed) == ChatFinishReason.tool_calls
  doAssert firstText(parsed) == "first"
  doAssert outputText(parsed) == "firstsecond"
  doAssert functionCalls(parsed).len == 1
  doAssert hasFunctionCalls(parsed)
  doAssert firstCallId(parsed) == "call_1"
  doAssert firstCallName(parsed) == "lookup"
  doAssert firstCallArgs(parsed) == "{\"q\":\"nim\"}"

proc testResponseAccessorsRaiseOnMissingChoice() =
  let empty = ChatResult()
  doAssert empty.id == ""
  doAssert empty.model == ""
  doAssert empty.choices.len == 0
  doAssert not hasUsage(empty)

  expectValueError(finish(empty))
  expectValueError(finish(empty, i = 6))
  expectValueError(firstText(empty))
  expectValueError(firstText(empty, i = 2))
  expectValueError(outputText(empty))
  expectValueError(functionCalls(empty))
  expectValueError(hasFunctionCalls(empty))
  expectValueError(hasFunctionCalls(empty, i = 2))
  expectValueError(firstCallId(empty))
  expectValueError(firstCallName(empty))
  expectValueError(firstCallArgs(empty))
  expectValueError(usageOf(empty))
  expectValueError(inputTokens(empty))
  expectValueError(outputTokens(empty))
  expectValueError(totalTokens(empty))

  var withoutUsage: ChatResult
  doAssert chatParse(
    """{"id":"cmpl_no_usage","object":"chat.completion","created":1,"model":"m","choices":[]}""",
    withoutUsage
  )
  doAssert not hasUsage(withoutUsage)
  expectValueError(inputTokens(withoutUsage))

proc testVarCallsAccessor() =
  var parsed: ChatResult
  doAssert chatParse(PartsResponse, parsed)

  functionCalls(parsed).add(ChatToolCall(
    id: "call_2",
    `type`: ChatToolType.function,
    function: ChatFunctionCall(
      name: "other",
      arguments: "{}"
    )
  ))

  doAssert hasFunctionCalls(parsed)
  doAssert functionCalls(parsed).len == 2
  doAssert firstCallId(parsed) == "call_1"
  doAssert firstCallName(parsed) == "lookup"
  doAssert firstCallArgs(parsed) == "{\"q\":\"nim\"}"

proc testDirectResultFieldsAreMutable() =
  var parsed: ChatResult
  doAssert chatParse(PartsResponse, parsed)

  parsed.id = "cmpl_mut"
  parsed.model = "gpt-mut"
  parsed.choices[0].message.content.parts[0].text = "mut-first"
  parsed.choices[0].message.tool_calls[0].id = "call_mut"
  parsed.choices[0].message.tool_calls[0].function.name = "lookupMut"
  parsed.choices[0].message.tool_calls[0].function.arguments = "{\"q\":\"mut\"}"

  doAssert parsed.id == "cmpl_mut"
  doAssert parsed.model == "gpt-mut"
  doAssert firstText(parsed) == "mut-first"
  doAssert firstCallId(parsed) == "call_mut"
  doAssert firstCallName(parsed) == "lookupMut"
  doAssert firstCallArgs(parsed) == "{\"q\":\"mut\"}"

proc testParseFirstTextJson() =
  var parsed: ChatResult
  doAssert chatParse(JsonTextResponse, parsed)

  var answer: ParsedWeatherAnswer
  doAssert parseFirstTextJson(parsed, answer)
  doAssert answer.city == "Seattle"
  doAssert answer.temperatureC == 9.0
  doAssert answer.condition == "light rain"
  doAssert answer.advice == "Wear a jacket."

  parsed.choices[0].message.content.text =
    """{"city":"Seattle","temperatureC":9.0,"condition":"rain","advice":"coat","future":true}"""
  doAssert parseFirstTextJson(parsed, answer)

  doAssert not parseFirstTextJson(parsed, answer, i = 1)
  doAssert not parseFirstTextJson(parsed, answer, i = 3)

  var textOnly: ChatResult
  doAssert chatParse(GoodResponse, textOnly)
  doAssert not parseFirstTextJson(textOnly, answer)

proc testParseFirstCallArgs() =
  var parsed: ChatResult
  doAssert chatParse(PartsResponse, parsed)

  var args: ParsedToolArgs
  doAssert parseFirstCallArgs(parsed, args)
  doAssert args.q == "nim"

  parsed.choices[0].message.tool_calls[0].function.arguments =
    """{"q":"nim","future":true}"""
  doAssert parseFirstCallArgs(parsed, args)

  doAssert not parseFirstCallArgs(parsed, args, i = 3)

  var bad = parsed
  bad.choices[0].message.tool_calls[0].function.arguments = "{bad json"
  doAssert not parseFirstCallArgs(bad, args)

  var noCalls: ChatResult
  doAssert chatParse(GoodResponse, noCalls)
  doAssert not parseFirstCallArgs(noCalls, args)

proc testStoreAndCurrentFieldsSerialization() =
  let defaultRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")]
  )
  let defaultJson = toJson(defaultRequest)
  doAssert not defaultJson.contains("\"store\":")
  doAssert not defaultJson.contains("\"parallel_tool_calls\":")
  doAssert not defaultJson.contains("\"prompt_cache_key\":")

  let request = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    parallelToolCalls = false,
    metadata = RawJson("""{"suite":"chat"}"""),
    promptCacheKey = "cache-key",
    promptCacheOptions = PromptCacheOptions(
      mode: PromptCacheMode.explicit,
      ttl: PromptCacheTtl.thirtyMinutes
    ),
    safetyIdentifier = "hashed-user",
    serviceTier = "priority",
    store = true
  )
  let json = toJson(request)
  doAssert json.contains("\"parallel_tool_calls\":false")
  doAssert json.contains(""""metadata":{"suite":"chat"}""")
  doAssert json.contains("\"prompt_cache_key\":\"cache-key\"")
  doAssert json.contains(
    """"prompt_cache_options":{"mode":"explicit","ttl":"30m"}"""
  )
  doAssert json.contains("\"safety_identifier\":\"hashed-user\"")
  doAssert json.contains("\"service_tier\":\"priority\"")
  doAssert json.contains("\"store\":true")
  doAssert not json.contains("\"max_tokens\":")
  doAssert not json.contains("\"seed\":")
  doAssert not json.contains("\"prompt_cache_retention\":")

  let parsed = fromJson(json, ChatParams)
  doAssert not parsed.parallel_tool_calls
  doAssert parsed.prompt_cache_key == "cache-key"
  doAssert parsed.prompt_cache_options.mode == PromptCacheMode.explicit
  doAssert parsed.prompt_cache_options.ttl == PromptCacheTtl.thirtyMinutes
  doAssert parsed.store

proc testToolCallResponseWithNullContent() =
  var parsed: ChatResult
  doAssert chatParse(ToolCallResponse, parsed)
  doAssert parsed.`object` == "chat.completion"
  doAssert parsed.service_tier == "default"
  doAssert parsed.system_fingerprint.isNone
  doAssert parsed.choices[0].message.content.kind == ChatAssistantContentKind.none
  doAssert parsed.choices[0].message.refusal.isNone
  doAssert parsed.choices[0].message.annotations.len == 0
  doAssert parsed.usage.isSome
  doAssert parsed.usage.get.prompt_tokens_details.cached_tokens == 0
  doAssert parsed.usage.get.prompt_tokens_details.cache_write_tokens == 0
  doAssert parsed.usage.get.prompt_tokens_details.audio_tokens == 0
  doAssert parsed.usage.get.completion_tokens_details.reasoning_tokens == 10
  doAssert parsed.usage.get.completion_tokens_details.accepted_prediction_tokens == 0
  doAssert parsed.usage.get.completion_tokens_details.rejected_prediction_tokens == 0

when isMainModule:
  testInputConstructorsCoverage()
  testChatCreateParamsBuilder()
  testChatCreateMaxCompletionTokensSerialization()
  testChatCreateSerializationFieldInclusionRules()
  testAssistantToolCallMessageSerialization()
  testSerializationRoundTripForBuiltRequest()
  testChatRequest()
  testStreamingFlagPassesThrough()
  testChatAdd()
  testChatParse()
  testResponseGettersWithTextContent()
  testResponseGettersWithPartsAndToolCalls()
  testResponseAccessorsRaiseOnMissingChoice()
  testVarCallsAccessor()
  testDirectResultFieldsAreMutable()
  testParseFirstTextJson()
  testParseFirstCallArgs()
  testStoreAndCurrentFieldsSerialization()
  testToolCallResponseWithNullContent()
  echo "all tests passed"
