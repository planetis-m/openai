import relay
import jsonx
import openai
import std/strutils

const GoodResponse = """{
  "id": "cmpl_1",
  "model": "gpt-4.1-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": [],
        "content": "Hello"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 1,
    "completion_tokens": 2,
    "total_tokens": 3
  }
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
              "arguments": "{\"q\":\"nim\"}"
            }
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

type
  ParsedWeatherAnswer = object
    city: string
    temperatureC: float
    condition: string
    advice: string

  ParsedToolArgs = object
    q: string

proc sampleParams(streamValue = false): ChatCreateParams =
  chatCreate(
    model = "gpt-4.1-mini",
    stream = streamValue,
    temperature = 0.2,
    maxTokens = 64,
    responseFormat = formatText,
    messages = @[
      userMessageText("ping")
    ]
  )

proc sampleConfig(apiKey = "sk-test"): OpenAIConfig =
  OpenAIConfig(
    url: "https://api.openai.com/v1/chat/completions",
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
  doAssert req.url == cfg.url
  doAssert req.requestId == 42
  doAssert req.timeoutMs == 7_000
  doAssert req.headers["Authorization"] == "Bearer new-token"
  doAssert req.headers["Content-Type"] == "application/json"
  doAssert req.headers["X-Trace-Id"] == "trace-1"

  let payload = fromJson(req.body, ChatCreateParams)
  doAssert payload.model == "gpt-4.1-mini"
  doAssert payload.messages.len == 1
  doAssert payload.messages[0].content.kind == ChatCompletionInputContentKind.text
  doAssert payload.messages[0].content.text == "ping"

proc testInputConstructorsCoverage() =
  let pText = partText("plain")
  doAssert pText.`type` == ChatCompletionContentPartType.text
  doAssert pText.text == "plain"

  let pImg = partImageUrl("https://example.com/a.png", detail = ImageDetail.high)
  doAssert pImg.`type` == ChatCompletionContentPartType.image_url
  doAssert pImg.image_url.url == "https://example.com/a.png"
  doAssert pImg.image_url.detail == ImageDetail.high

  let pAudio = partInputAudio("base64audio", InputAudioFormat.mp3)
  doAssert pAudio.`type` == ChatCompletionContentPartType.input_audio
  doAssert pAudio.input_audio.data == "base64audio"
  doAssert pAudio.input_audio.format == InputAudioFormat.mp3

  let cText = contentText("hello")
  doAssert cText.kind == ChatCompletionInputContentKind.text
  doAssert cText.text == "hello"

  let cParts = contentParts(@[pText, pImg, pAudio])
  doAssert cParts.kind == ChatCompletionInputContentKind.parts
  doAssert cParts.parts.len == 3
  doAssert cParts.parts[1].`type` == ChatCompletionContentPartType.image_url

  let mSystem = systemMessageText("rules", name = "sys")
  doAssert mSystem.role == ChatMessageRole.system
  doAssert mSystem.content.kind == ChatCompletionInputContentKind.text
  doAssert mSystem.content.text == "rules"
  doAssert mSystem.name == "sys"

  let mUserText = userMessageText("ask")
  doAssert mUserText.role == ChatMessageRole.user
  doAssert mUserText.content.kind == ChatCompletionInputContentKind.text
  doAssert mUserText.content.text == "ask"

  let mUserParts = userMessageParts(@[pText, pImg], name = "u")
  doAssert mUserParts.role == ChatMessageRole.user
  doAssert mUserParts.content.kind == ChatCompletionInputContentKind.parts
  doAssert mUserParts.content.parts.len == 2
  doAssert mUserParts.name == "u"

  let mAssistant = assistantMessageText("draft")
  doAssert mAssistant.role == ChatMessageRole.assistant
  doAssert mAssistant.content.kind == ChatCompletionInputContentKind.text
  doAssert mAssistant.content.text == "draft"

  let toolCall = ChatCompletionMessageToolCall(
    id: "call_1",
    `type`: ChatToolType.function,
    function: FunctionCall(
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
  doAssert mTool.content.kind == ChatCompletionInputContentKind.text
  doAssert mTool.content.text == "result-json"
  doAssert mTool.tool_call_id == "call_99"
  doAssert mTool.name == "tool-name"

  let mToolJson = toolMessageJson((city: "Berlin", celsius: 3.5), "call_100",
    name = "weather")
  doAssert mToolJson.role == ChatMessageRole.tool
  doAssert mToolJson.content.kind == ChatCompletionInputContentKind.text
  doAssert mToolJson.content.text == """{"city":"Berlin","celsius":3.5}"""
  doAssert mToolJson.tool_call_id == "call_100"
  doAssert mToolJson.name == "weather"

  let tool = toolFunction("lookup", "search docs")
  doAssert tool.`type` == ChatToolType.function
  doAssert tool.function.name == "lookup"
  doAssert tool.function.description == "search docs"
  doAssert tool.function.parameters == EmptyFunctionParametersSchema

  type
    ToolSchema = object
      `type`: string

  let typedTool = toolFunction("typed", ToolSchema(`type`: "object"))
  doAssert typedTool.function.parameters == """{"type":"object"}"""

  doAssert formatText.`type` == ResponseFormatType.text
  doAssert formatJsonObject.`type` == ResponseFormatType.json_object
  let jsonSchemaFormat = formatJsonSchema("output", """{"type":"object"}""")
  doAssert jsonSchemaFormat.`type` == ResponseFormatType.json_schema
  doAssert jsonSchemaFormat.json_schema.name == "output"
  doAssert jsonSchemaFormat.json_schema.schema == """{"type":"object"}"""
  doAssert jsonSchemaFormat.json_schema.strict
  doAssert formatRegex.`type` == ResponseFormatType.regex

proc testChatCreateParamsBuilder() =
  let request = chatCreate(
    model = "gpt-4.1",
    messages = @[systemMessageText("sys"), userMessageParts(@[partText("what?")])],
    stream = true,
    temperature = 0.75,
    maxTokens = 321,
    tools = @[toolFunction("calc", "math")],
    toolChoice = ToolChoice.required,
    responseFormat = formatJsonObject
  )

  doAssert request.model == "gpt-4.1"
  doAssert request.messages.len == 2
  doAssert request.messages[1].content.kind == ChatCompletionInputContentKind.parts
  doAssert request.stream
  doAssert request.temperature == 0.75
  doAssert request.max_tokens == 321
  doAssert request.tools.len == 1
  doAssert request.tools[0].function.name == "calc"
  doAssert request.tool_choice == ToolChoice.required
  doAssert request.response_format.`type` == ResponseFormatType.json_object

proc testChatCreateMaxTokensSerialization() =
  let defaultRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")]
  )
  let defaultJson = toJson(defaultRequest)
  doAssert not defaultJson.contains("\"max_tokens\":")
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
    maxTokens = 64
  )
  let explicitJson = toJson(explicitRequest)
  doAssert explicitJson.contains("\"max_tokens\":64")

proc testChatCreateSerializationFieldInclusionRules() =
  let request = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      userMessageText("ping", name = "alice"),
      toolMessageText("result", "call_1")
    ],
    stream = true,
    temperature = 0.2,
    maxTokens = 64,
    tools = @[
      toolFunction("lookup", "search docs"),
      toolFunction("extract")
    ],
    toolChoice = ToolChoice.required,
    responseFormat = formatJsonObject
  )
  let json = toJson(request)
  doAssert json.contains("\"stream\":true")
  doAssert json.contains("\"temperature\":0.2")
  doAssert json.contains("\"tool_choice\":\"required\"")
  doAssert json.contains("\"response_format\":{\"type\":\"json_object\"}")
  doAssert json.contains("\"name\":\"alice\"")
  doAssert json.contains("\"tool_call_id\":\"call_1\"")
  doAssert json.contains("\"name\":\"lookup\",\"description\":\"search docs\",\"parameters\":{\"type\":\"object\",\"properties\":{}}")
  doAssert not json.contains("\"name\":\"extract\",\"description\":")

  let noToolsRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    toolChoice = ToolChoice.required
  )
  let noToolsJson = toJson(noToolsRequest)
  doAssert not noToolsJson.contains("\"tools\":")
  doAssert not noToolsJson.contains("\"tool_choice\":")

  let toolsDefaultChoiceRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    tools = @[toolFunction("lookup")]
  )
  let toolsDefaultChoiceJson = toJson(toolsDefaultChoiceRequest)
  doAssert toolsDefaultChoiceJson.contains("\"tools\":[")
  doAssert not toolsDefaultChoiceJson.contains("\"tool_choice\":")

  let toolsAutoChoiceRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("ping")],
    tools = @[toolFunction("lookup")],
    toolChoice = ToolChoice.auto
  )
  let toolsAutoChoiceJson = toJson(toolsAutoChoiceRequest)
  doAssert toolsAutoChoiceJson.contains("\"tools\":[")
  doAssert not toolsAutoChoiceJson.contains("\"tool_choice\":")

proc testAssistantToolCallMessageSerialization() =
  let toolCall = ChatCompletionMessageToolCall(
    id: "call_1",
    `type`: ChatToolType.function,
    function: FunctionCall(
      name: "lookup",
      arguments: "{\"q\":\"nim\"}"
    )
  )

  let toolCallOnlyRequest = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[
      assistantMessageToolCalls(@[toolCall])
    ],
    tools = @[toolFunction("lookup")]
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
    tools = @[toolFunction("lookup")]
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
        partImageUrl("https://example.com/1.jpg", detail = ImageDetail.low),
        partInputAudio("ZGF0YQ==", InputAudioFormat.wav)
      ])
    ],
    maxTokens = 128,
    responseFormat = formatText
  )
  let serialized = toJson(request)
  let parsed = fromJson(serialized, ChatCreateParams)
  doAssert parsed.model == request.model
  doAssert parsed.messages.len == 1
  doAssert parsed.messages[0].content.kind == ChatCompletionInputContentKind.parts
  doAssert parsed.messages[0].content.parts.len == 3
  doAssert parsed.messages[0].content.parts[1].image_url.detail == ImageDetail.low

proc testStreamingFlagPassesThrough() =
  let cfg = sampleConfig()
  let req = chatRequest(cfg, sampleParams(streamValue = true))
  let payload = fromJson(req.body, ChatCreateParams)
  doAssert payload.stream

proc testChatAdd() =
  let cfg = sampleConfig(apiKey = "batch-token")
  var batch: RequestBatch
  chatAdd(batch, cfg, sampleParams(), requestId = 11, timeoutMs = 1_500)
  chatAdd(batch, cfg, sampleParams(), requestId = 12)

  doAssert batch.len == 2
  doAssert batch[0].verb == hvPost
  doAssert batch[0].url == cfg.url
  doAssert batch[0].requestId == 11
  doAssert batch[0].timeoutMs == 1_500
  doAssert batch[0].headers["Authorization"] == "Bearer batch-token"
  doAssert batch[0].headers["Content-Type"] == "application/json"
  doAssert batch[1].requestId == 12

proc testChatParse() =
  var decoded: ChatCreateResult
  doAssert chatParse(GoodResponse, decoded)
  doAssert decoded.id == "cmpl_1"
  doAssert decoded.model == "gpt-4.1-mini"
  doAssert decoded.choices.len == 1
  doAssert decoded.choices[0].message.content.kind == ChatCompletionAssistantContentKind.text
  doAssert decoded.choices[0].message.content.text == "Hello"
  doAssert decoded.usage.total_tokens == 3

  var bad: ChatCreateResult
  doAssert not chatParse("{", bad)

proc testResponseGettersWithTextContent() =
  var parsed: ChatCreateResult
  doAssert chatParse(GoodResponse, parsed)
  doAssert idOf(parsed) == "cmpl_1"
  doAssert modelOf(parsed) == "gpt-4.1-mini"
  doAssert choices(parsed) == 1
  doAssert finish(parsed) == FinishReason.stop
  doAssert firstText(parsed) == "Hello"
  doAssert allTextParts(parsed).len == 0
  doAssert promptTokens(parsed) == 1
  doAssert completionTokens(parsed) == 2
  doAssert totalTokens(parsed) == 3
  doAssert calls(parsed).len == 0
  doAssert not hasToolCalls(parsed)
  doAssert firstCallId(parsed) == ""
  doAssert firstCallName(parsed) == ""
  doAssert firstCallArgs(parsed) == ""

proc testResponseGettersWithPartsAndToolCalls() =
  var parsed: ChatCreateResult
  doAssert chatParse(PartsResponse, parsed)
  doAssert finish(parsed) == FinishReason.tool_calls
  doAssert firstText(parsed) == "first"
  doAssert allTextParts(parsed) == @["first", "second"]
  doAssert calls(parsed).len == 1
  doAssert hasToolCalls(parsed)
  doAssert firstCallId(parsed) == "call_1"
  doAssert firstCallName(parsed) == "lookup"
  doAssert firstCallArgs(parsed) == "{\"q\":\"nim\"}"

proc testResponseGetterDefaultsOnMissingChoice() =
  let empty = ChatCreateResult()
  doAssert idOf(empty) == ""
  doAssert modelOf(empty) == ""
  doAssert choices(empty) == 0
  doAssert finish(empty) == FinishReason.unknown
  doAssert finish(empty, i = 6) == FinishReason.unknown
  doAssert firstText(empty) == ""
  doAssert firstText(empty, i = 2) == ""
  doAssert allTextParts(empty).len == 0
  doAssert calls(empty).len == 0
  doAssert not hasToolCalls(empty)
  doAssert not hasToolCalls(empty, i = 2)
  doAssert firstCallId(empty) == ""
  doAssert firstCallName(empty) == ""
  doAssert firstCallArgs(empty) == ""
  doAssert promptTokens(empty) == 0
  doAssert completionTokens(empty) == 0
  doAssert totalTokens(empty) == 0

proc testParseFirstTextJson() =
  var parsed: ChatCreateResult
  doAssert chatParse(JsonTextResponse, parsed)

  var answer: ParsedWeatherAnswer
  doAssert parseFirstTextJson(parsed, answer)
  doAssert answer.city == "Seattle"
  doAssert answer.temperatureC == 9.0
  doAssert answer.condition == "light rain"
  doAssert answer.advice == "Wear a jacket."

  doAssert not parseFirstTextJson(parsed, answer, i = 1)
  doAssert not parseFirstTextJson(parsed, answer, i = 3)

  var textOnly: ChatCreateResult
  doAssert chatParse(GoodResponse, textOnly)
  doAssert not parseFirstTextJson(textOnly, answer)

proc testParseFirstCallArgs() =
  var parsed: ChatCreateResult
  doAssert chatParse(PartsResponse, parsed)

  var args: ParsedToolArgs
  doAssert parseFirstCallArgs(parsed, args)
  doAssert args.q == "nim"

  doAssert not parseFirstCallArgs(parsed, args, i = 3)

  var bad = parsed
  bad.choices[0].message.tool_calls[0].function.arguments = "{bad json"
  doAssert not parseFirstCallArgs(bad, args)

  var noCalls: ChatCreateResult
  doAssert chatParse(GoodResponse, noCalls)
  doAssert not parseFirstCallArgs(noCalls, args)

proc testHttpSuccessClassifier() =
  doAssert isHttpSuccess(200)
  doAssert isHttpSuccess(201)
  doAssert isHttpSuccess(204)
  doAssert not isHttpSuccess(199)
  doAssert not isHttpSuccess(300)
  doAssert not isHttpSuccess(429)
  doAssert not isHttpSuccess(500)

when isMainModule:
  testInputConstructorsCoverage()
  testChatCreateParamsBuilder()
  testChatCreateMaxTokensSerialization()
  testChatCreateSerializationFieldInclusionRules()
  testAssistantToolCallMessageSerialization()
  testSerializationRoundTripForBuiltRequest()
  testChatRequest()
  testStreamingFlagPassesThrough()
  testChatAdd()
  testChatParse()
  testResponseGettersWithTextContent()
  testResponseGettersWithPartsAndToolCalls()
  testResponseGetterDefaultsOnMissingChoice()
  testParseFirstTextJson()
  testParseFirstCallArgs()
  testHttpSuccessClassifier()
  echo "all tests passed"
