import relay
import jsonx
import ../openai

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

proc sampleParams(streamValue = false): ResponsesCreateParams =
  responsesCreateParams(
    model = "gpt-4.1-mini",
    stream = streamValue,
    temperature = 0.2,
    maxTokens = 64,
    responseFormat = responseFormatText(),
    messages = [
      msgUserText("ping")
    ]
  )

proc sampleConfig(apiKey = "sk-test"): EndpointConfig =
  EndpointConfig(
    url: "https://api.openai.com/v1/chat/completions",
    apiKey: apiKey
  )

proc testResponsesCreateRequest() =
  let cfg = sampleConfig(apiKey = "new-token")
  var headers = emptyHttpHeaders()
  headers["Authorization"] = "Bearer old-token"
  headers["Content-Type"] = "text/plain"
  headers["X-Trace-Id"] = "trace-1"

  let req = responsesCreateRequest(
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

  let payload = fromJson(req.body, ResponsesCreateParams)
  doAssert payload.model == "gpt-4.1-mini"
  doAssert payload.messages.len == 1
  doAssert payload.messages[0].content.kind == ChatCompletionInputContentKind.text
  doAssert payload.messages[0].content.text == "ping"

proc testInputConstructorsCoverage() =
  let pText = textPart("plain")
  doAssert pText.`type` == ChatCompletionContentPartType.text
  doAssert pText.text == "plain"

  let pImg = imageUrlPart("https://example.com/a.png", detail = ImageDetail.high)
  doAssert pImg.`type` == ChatCompletionContentPartType.image_url
  doAssert pImg.image_url.url == "https://example.com/a.png"
  doAssert pImg.image_url.detail == ImageDetail.high

  let pAudio = inputAudioPart("base64audio", InputAudioFormat.mp3)
  doAssert pAudio.`type` == ChatCompletionContentPartType.input_audio
  doAssert pAudio.input_audio.data == "base64audio"
  doAssert pAudio.input_audio.format == InputAudioFormat.mp3

  let cText = textContent("hello")
  doAssert cText.kind == ChatCompletionInputContentKind.text
  doAssert cText.text == "hello"

  let cParts = partsContent([pText, pImg, pAudio])
  doAssert cParts.kind == ChatCompletionInputContentKind.parts
  doAssert cParts.parts.len == 3
  doAssert cParts.parts[1].`type` == ChatCompletionContentPartType.image_url

  let mSystem = msgSystem("rules", name = "sys")
  doAssert mSystem.role == ChatMessageRole.system
  doAssert mSystem.content.kind == ChatCompletionInputContentKind.text
  doAssert mSystem.content.text == "rules"
  doAssert mSystem.name == "sys"

  let mUserText = msgUserText("ask")
  doAssert mUserText.role == ChatMessageRole.user
  doAssert mUserText.content.kind == ChatCompletionInputContentKind.text
  doAssert mUserText.content.text == "ask"

  let mUserParts = msgUserParts([pText, pImg], name = "u")
  doAssert mUserParts.role == ChatMessageRole.user
  doAssert mUserParts.content.kind == ChatCompletionInputContentKind.parts
  doAssert mUserParts.content.parts.len == 2
  doAssert mUserParts.name == "u"

  let mAssistant = msgAssistant("draft")
  doAssert mAssistant.role == ChatMessageRole.assistant
  doAssert mAssistant.content.kind == ChatCompletionInputContentKind.text
  doAssert mAssistant.content.text == "draft"

  let mTool = msgTool("result-json", "call_99", name = "tool-name")
  doAssert mTool.role == ChatMessageRole.tool
  doAssert mTool.content.kind == ChatCompletionInputContentKind.text
  doAssert mTool.content.text == "result-json"
  doAssert mTool.tool_call_id == "call_99"
  doAssert mTool.name == "tool-name"

  let tool = functionTool("lookup", "search docs")
  doAssert tool.`type` == ChatToolType.function
  doAssert tool.function.name == "lookup"
  doAssert tool.function.description == "search docs"

  doAssert responseFormatText().`type` == ResponseFormatType.text
  doAssert responseFormatJsonObject().`type` == ResponseFormatType.json_object
  doAssert responseFormatJsonSchema().`type` == ResponseFormatType.json_schema
  doAssert responseFormatRegex().`type` == ResponseFormatType.regex

proc testResponsesCreateParamsBuilder() =
  let request = responsesCreateParams(
    model = "gpt-4.1",
    messages = [msgSystem("sys"), msgUserParts([textPart("what?")])],
    stream = true,
    temperature = 0.75,
    maxTokens = 321,
    tools = [functionTool("calc", "math")],
    toolChoice = ToolChoice.required,
    responseFormat = responseFormatJsonObject()
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

proc testSerializationRoundTripForBuiltRequest() =
  let request = responsesCreateParams(
    model = "gpt-4.1-mini",
    messages = [
      msgUserParts([
        textPart("describe"),
        imageUrlPart("https://example.com/1.jpg", detail = ImageDetail.low),
        inputAudioPart("ZGF0YQ==", InputAudioFormat.wav)
      ])
    ],
    maxTokens = 128,
    tools = [functionTool("extract")],
    responseFormat = responseFormatText()
  )
  let serialized = toJson(request)
  let parsed = fromJson(serialized, ResponsesCreateParams)
  doAssert parsed.model == request.model
  doAssert parsed.messages.len == 1
  doAssert parsed.messages[0].content.kind == ChatCompletionInputContentKind.parts
  doAssert parsed.messages[0].content.parts.len == 3
  doAssert parsed.messages[0].content.parts[1].image_url.detail == ImageDetail.low

proc testStreamingFlagPassesThrough() =
  let cfg = sampleConfig()
  let req = responsesCreateRequest(cfg, sampleParams(streamValue = true))
  let payload = fromJson(req.body, ResponsesCreateParams)
  doAssert payload.stream

proc testAddResponsesCreate() =
  let cfg = sampleConfig(apiKey = "batch-token")
  var batch: RequestBatch
  addResponsesCreate(batch, cfg, sampleParams(), requestId = 11, timeoutMs = 1_500)
  addResponsesCreate(batch, cfg, sampleParams(), requestId = 12)

  doAssert batch.len == 2
  doAssert batch[0].verb == hvPost
  doAssert batch[0].url == cfg.url
  doAssert batch[0].requestId == 11
  doAssert batch[0].timeoutMs == 1_500
  doAssert batch[0].headers["Authorization"] == "Bearer batch-token"
  doAssert batch[0].headers["Content-Type"] == "application/json"
  doAssert batch[1].requestId == 12

proc testTryDecodeResponsesCreate() =
  var decoded: ResponsesCreateResult
  doAssert tryDecodeResponsesCreate(GoodResponse, decoded)
  doAssert decoded.id == "cmpl_1"
  doAssert decoded.model == "gpt-4.1-mini"
  doAssert decoded.choices.len == 1
  doAssert decoded.choices[0].message.content.kind == ChatCompletionAssistantContentKind.text
  doAssert decoded.choices[0].message.content.text == "Hello"
  doAssert decoded.usage.total_tokens == 3

  var bad: ResponsesCreateResult
  doAssert not tryDecodeResponsesCreate("{", bad)

proc testResponseGettersWithTextContent() =
  var parsed: ResponsesCreateResult
  doAssert tryDecodeResponsesCreate(GoodResponse, parsed)
  doAssert responseId(parsed) == "cmpl_1"
  doAssert responseModel(parsed) == "gpt-4.1-mini"
  doAssert choiceCount(parsed) == 1
  doAssert finishReason(parsed) == "stop"
  doAssert assistantText(parsed) == "Hello"
  doAssert assistantPartsText(parsed).len == 0
  doAssert usagePromptTokens(parsed) == 1
  doAssert usageCompletionTokens(parsed) == 2
  doAssert usageTotalTokens(parsed) == 3
  doAssert toolCalls(parsed).len == 0
  doAssert firstToolCallName(parsed) == ""
  doAssert firstToolCallArguments(parsed) == ""

proc testResponseGettersWithPartsAndToolCalls() =
  var parsed: ResponsesCreateResult
  doAssert tryDecodeResponsesCreate(PartsResponse, parsed)
  doAssert finishReason(parsed) == "tool_calls"
  doAssert assistantText(parsed) == "first"
  doAssert assistantPartsText(parsed) == @["first", "second"]
  doAssert toolCalls(parsed).len == 1
  doAssert firstToolCallName(parsed) == "lookup"
  doAssert firstToolCallArguments(parsed) == "{\"q\":\"nim\"}"

proc testResponseGetterDefaultsOnMissingChoice() =
  let empty = ResponsesCreateResult()
  doAssert responseId(empty) == ""
  doAssert responseModel(empty) == ""
  doAssert choiceCount(empty) == 0
  doAssert finishReason(empty) == ""
  doAssert finishReason(empty, i = 6) == ""
  doAssert assistantText(empty) == ""
  doAssert assistantText(empty, i = 2) == ""
  doAssert assistantPartsText(empty).len == 0
  doAssert toolCalls(empty).len == 0
  doAssert firstToolCallName(empty) == ""
  doAssert firstToolCallArguments(empty) == ""
  doAssert usagePromptTokens(empty) == 0
  doAssert usageCompletionTokens(empty) == 0
  doAssert usageTotalTokens(empty) == 0

proc testHttpSuccessClassifier() =
  doAssert isHttpSuccess(200)
  doAssert isHttpSuccess(201)
  doAssert isHttpSuccess(204)
  doAssert not isHttpSuccess(199)
  doAssert not isHttpSuccess(300)
  doAssert not isHttpSuccess(429)
  doAssert not isHttpSuccess(500)

proc testRetriableTransportClassifier() =
  doAssert not isRetriableTransport(teNone)
  doAssert isRetriableTransport(teTimeout)
  doAssert isRetriableTransport(teNetwork)
  doAssert isRetriableTransport(teDns)
  doAssert isRetriableTransport(teTls)
  doAssert isRetriableTransport(teInternal)
  doAssert not isRetriableTransport(teCanceled)
  doAssert not isRetriableTransport(teProtocol)

proc testRetriableStatusClassifier() =
  doAssert isRetriableStatus(408)
  doAssert isRetriableStatus(409)
  doAssert isRetriableStatus(425)
  doAssert isRetriableStatus(429)
  doAssert isRetriableStatus(500)
  doAssert isRetriableStatus(503)
  doAssert not isRetriableStatus(200)
  doAssert not isRetriableStatus(400)
  doAssert not isRetriableStatus(404)

when isMainModule:
  testInputConstructorsCoverage()
  testResponsesCreateParamsBuilder()
  testSerializationRoundTripForBuiltRequest()
  testResponsesCreateRequest()
  testStreamingFlagPassesThrough()
  testAddResponsesCreate()
  testTryDecodeResponsesCreate()
  testResponseGettersWithTextContent()
  testResponseGettersWithPartsAndToolCalls()
  testResponseGetterDefaultsOnMissingChoice()
  testHttpSuccessClassifier()
  testRetriableTransportClassifier()
  testRetriableStatusClassifier()
  echo "all tests passed"
