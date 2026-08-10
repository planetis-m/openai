import std/[assertions, strutils]
import relay
import jsonx
import jsonx/parsejson
import openai/responses

const GoodResponse = """{
  "id": "resp_1",
  "object": "response",
  "created_at": 1786200000,
  "completed_at": 1786200001,
  "background": false,
  "status": "completed",
  "error": null,
  "incomplete_details": null,
  "model": "gpt-5.6-luna",
  "output": [
    {
      "id": "msg_1",
      "type": "message",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "{\"answer\":42}",
          "annotations": [],
          "logprobs": [],
          "future_content_field": true
        }
      ]
    },
    {
      "id": "fc_1",
      "type": "function_call",
      "status": "completed",
      "call_id": "call_1",
      "name": "lookup",
      "arguments": "{\"q\":\"nim\"}",
      "future_item_field": {}
    }
  ],
  "previous_response_id": null,
  "service_tier": "default",
  "usage": {
    "input_tokens": 20,
    "input_tokens_details": {"cached_tokens": 5, "cache_write_tokens": 2},
    "output_tokens": 9,
    "output_tokens_details": {"reasoning_tokens": 3},
    "total_tokens": 29
  },
  "metadata": {},
  "reasoning": {"effort":"low"},
  "truncation": "disabled",
  "user": null,
  "future_response_field": "ignored"
}"""

type
  Answer = object
    answer: int

  CallArgs = object
    q: string

proc sampleConfig(): OpenAIConfig =
  OpenAIConfig(apiKey: "sk-test")

block request_scalar_defaults:
  let defaults = responseCreate("gpt-5.6-luna", inputText("Hello"))
  doAssert defaults.parallel_tool_calls
  doAssert defaults.store
  doAssert defaults.temperature == 1.0
  doAssert defaults.top_logprobs == 0
  doAssert defaults.top_p == 1.0
  let defaultBody = toJson(defaults)
  doAssert not defaultBody.contains("\"parallel_tool_calls\":")
  doAssert not defaultBody.contains("\"store\":")
  doAssert not defaultBody.contains("\"temperature\":")
  doAssert not defaultBody.contains("\"top_logprobs\":")
  doAssert not defaultBody.contains("\"top_p\":")
  doAssert not defaultBody.contains("\"prompt_cache_options\":")

  let explicit = responseCreate("gpt-5.6-luna", inputText("Hello"),
    background = true, parallelToolCalls = false, store = false,
    temperature = 0.0, topLogprobs = 5, topP = 0.9)
  let explicitBody = toJson(explicit)
  doAssert explicitBody.contains("\"background\":true")
  doAssert explicitBody.contains("\"parallel_tool_calls\":false")
  doAssert explicitBody.contains("\"store\":false")
  doAssert explicitBody.contains("\"temperature\":0.0")
  doAssert explicitBody.contains("\"top_logprobs\":5")
  doAssert explicitBody.contains("\"top_p\":0.9")

  let cached = responseCreate("gpt-5.6-luna", inputText("Hello"),
    promptCacheKey = "cache-key",
    promptCacheOptions = PromptCacheOptions(
      mode: PromptCacheMode.explicit,
      ttl: PromptCacheTtl.thirtyMinutes
    ))
  let cachedBody = toJson(cached)
  doAssert cachedBody.contains("\"prompt_cache_key\":\"cache-key\"")
  doAssert cachedBody.contains(
    "\"prompt_cache_options\":{\"mode\":\"explicit\",\"ttl\":\"30m\"}")
  let decoded = fromJson(
    """{"mode":"explicit","ttl":"30m"}""",
    PromptCacheOptions
  )
  doAssert decoded.mode == PromptCacheMode.explicit
  doAssert decoded.ttl == PromptCacheTtl.thirtyMinutes
  doAssertRaises JsonParsingError:
    discard fromJson(
      """{"mode":"automatic","ttl":"30m"}""",
      PromptCacheOptions
    )

block simple_text_request:
  let params = responseCreate(
    model = "gpt-5.6-luna",
    input = inputText("Hello"),
    instructions = "Be concise.",
    maxOutputTokens = 128,
    reasoning = ResponseReasoning(effort: ResponseReasoningEffort.low),
    store = false
  )
  let body = toJson(params)
  doAssert body ==
    """{"model":"gpt-5.6-luna","input":"Hello","instructions":"Be concise.",""" &
    """"max_output_tokens":128,"reasoning":{"effort":"low"},"store":false}"""
  doAssert not body.contains("prompt_cache_retention")
  doAssert not body.contains("truncation")
  doAssert not body.contains("\"user\"")

block message_content:
  let text = contentText("Hello")
  doAssert text.kind == ResponseContentKind.text
  doAssert text.text == "Hello"
  doAssert toJson(text) == "\"Hello\""

  let parts = contentParts(@[
    partText("What is shown?"),
    partImageUrl("https://example.com/image.png")
  ])
  doAssert parts.kind == ResponseContentKind.parts
  doAssert parts.parts.len == 2
  doAssert toJson(parts) ==
    """[{"type":"input_text","text":"What is shown?"},""" &
    """{"type":"input_image","image_url":"https://example.com/image.png","detail":"auto"}]"""

  let decodedText = fromJson("\"decoded\"", ResponseContent)
  doAssert decodedText.kind == ResponseContentKind.text
  doAssert decodedText.text == "decoded"
  doAssertRaises JsonParsingError:
    discard fromJson("null", ResponseContent)

  let decodedParts = fromJson(
    """[{"type":"input_text","text":"decoded","future":true}]""",
    ResponseContent
  )
  doAssert decodedParts.kind == ResponseContentKind.parts
  doAssert decodedParts.parts[0].text == "decoded"
  doAssertRaises JsonParsingError:
    discard fromJson(
      """[{"type":"input_text","text":"decoded","future":true}]""",
      ResponseContent,
      unknownFields = ufReject
    )

  let message = messageText(ResponseRole.user, "Hello")
  doAssert message.role == ResponseRole.user
  doAssert message.content.kind == ResponseContentKind.text
  doAssert toJson(message) ==
    """{"role":"user","content":"Hello"}"""

  let decodedMessage = fromJson(
    """{"role":"user","content":"decoded","future":true}""",
    ResponseMessage
  )
  doAssert decodedMessage.content.text == "decoded"
  doAssertRaises JsonParsingError:
    discard fromJson(
      """{"role":"user","content":"decoded","future":true}""",
      ResponseMessage,
      unknownFields = ufReject
    )

block message_parts_and_tools:
  let message = messageParts(ResponseRole.user, @[
    partText("What is shown?"),
    partImageUrl("https://example.com/image.png", detail = "high"),
    partFileId("file_1")
  ])
  let tool = functionTool(
    "lookup",
    "Look up a value",
    RawJson("""{"type":"object","properties":{"q":{"type":"string"}}}""")
  )
  doAssert tool.`type` == ResponseToolType.function
  doAssert tool.name == "lookup"
  doAssert tool.description == "Look up a value"
  doAssert tool.strict
  doAssert toJson(functionTool("empty")) ==
    """{"type":"function","name":"empty","parameters":""" &
    """{"type":"object","properties":{}},"strict":true}"""
  let params = responseCreate(
    "gpt-5.6-luna",
    inputItems(@[RawJson(toJson(message))]),
    tools = @[RawJson(toJson(tool))],
    toolChoice = ResponseToolChoiceRequired,
    text = ResponseTextConfig(format: formatJsonSchema(
      "answer", RawJson("""{"type":"object"}""")
    ))
  )
  let body = toJson(params)
  doAssert body.contains("\"type\":\"input_text\"")
  doAssert body.contains("\"type\":\"input_image\"")
  doAssert body.contains("\"type\":\"input_file\"")
  doAssert body.contains("\"tool_choice\":\"required\"")
  doAssert body.contains("\"type\":\"json_schema\"")
  let namedChoice = toolChoiceFunction("lookup")
  doAssert namedChoice.`type` == ResponseToolType.function
  doAssert namedChoice.name == "lookup"
  doAssert toJson(namedChoice) ==
    """{"type":"function","name":"lookup"}"""

  let decodedChoice = fromJson(
    """{"type":"function","name":"decoded","future":true}""",
    ResponseToolChoice
  )
  doAssert decodedChoice.name == "decoded"
  doAssertRaises JsonParsingError:
    discard fromJson(
      """{"type":"function","name":"decoded","future":true}""",
      ResponseToolChoice,
      unknownFields = ufReject
    )

block function_outputs:
  let textOutput = functionOutput("call_1", "done")
  doAssert textOutput.call_id == "call_1"
  doAssert textOutput.output.kind == ResponseContentKind.text
  doAssert textOutput.output.text == "done"
  doAssert toJson(textOutput) ==
    """{"type":"function_call_output","call_id":"call_1","output":"done"}"""

  let jsonOutput = functionOutputJson("call_1", Answer(answer: 42))
  doAssert jsonOutput.output.text == "{\"answer\":42}"
  doAssert toJson(jsonOutput) ==
    """{"type":"function_call_output","call_id":"call_1","output":"{\"answer\":42}"}"""

  let partsOutput = functionOutputParts("call_1", @[
    partText("done"),
    partImageFile("file_1")
  ])
  doAssert partsOutput.output.kind == ResponseContentKind.parts
  doAssert toJson(partsOutput) ==
    """{"type":"function_call_output","call_id":"call_1","output":[""" &
    """{"type":"input_text","text":"done"},""" &
    """{"type":"input_image","file_id":"file_1","detail":"auto"}]}"""

  let decodedOutput = fromJson(
    """{"type":"function_call_output","call_id":"call_2","output":"ok","future":true}""",
    ResponseFunctionOutput
  )
  doAssert decodedOutput.call_id == "call_2"
  doAssert decodedOutput.output.text == "ok"
  doAssertRaises JsonParsingError:
    discard fromJson(
      """{"type":"function_call_output","call_id":"call_2","output":"ok","future":true}""",
      ResponseFunctionOutput,
      unknownFields = ufReject
    )

block request_and_batch:
  let cfg = sampleConfig()
  let params = responseCreate("gpt-5.6-luna", inputText("Hi"))
  let req = responseRequest(cfg, params, requestId = 12, timeoutMs = 3000)
  doAssert req.verb == hvPost
  doAssert req.url == OpenAIBaseUrl & "/responses"
  doAssert req.requestId == 12
  doAssert req.timeoutMs == 3000
  var batch: RequestBatch
  responseAdd(batch, cfg, params, requestId = 13)
  doAssert batch.len == 1
  doAssert batch[0].url == OpenAIBaseUrl & "/responses"

block parse_and_access:
  var parsed: ResponseResult
  doAssert responseParse(GoodResponse, parsed)
  doAssert parsed.id == "resp_1"
  doAssert parsed.model == "gpt-5.6-luna"
  doAssert createdAt(parsed) == 1786200000.0
  doAssert parsed.output.len == 2
  doAssert parsed.output[0].`type` == ResponseOutputKind.message
  doAssert parsed.output[0].content[0].`type` ==
    ResponseOutputPartType.output_text
  doAssert parsed.output[1].`type` == ResponseOutputKind.function_call
  doAssert firstText(parsed) == "{\"answer\":42}"
  doAssert outputText(parsed) == "{\"answer\":42}"
  doAssertRaises ValueError:
    discard outputItem(parsed, -1)
  doAssert outputItem(parsed, 1).`type` == ResponseOutputKind.function_call
  doAssert firstCallId(parsed) == "call_1"
  doAssert firstCallName(parsed) == "lookup"
  doAssert firstCallArgs(parsed) == "{\"q\":\"nim\"}"
  doAssert functionCalls(parsed).len == 1
  doAssert hasFunctionCalls(parsed)
  doAssert hasUsage(parsed)
  doAssert inputTokens(parsed) == 20
  doAssert cachedInputTokens(parsed) == 5
  doAssert cacheWriteTokens(parsed) == 2
  doAssert outputTokens(parsed) == 9
  doAssert reasoningTokens(parsed) == 3
  doAssert totalTokens(parsed) == 29
  var answer: Answer
  doAssert parseFirstTextJson(parsed, answer)
  doAssert answer.answer == 42
  var args: CallArgs
  doAssert parseFirstCallArgs(parsed, args)
  doAssert args.q == "nim"

  parsed.output[0].content[0].text = """{"answer":42,"future":true}"""
  doAssert parseFirstTextJson(parsed, answer)
  parsed.output[1].arguments = """{"q":"nim","future":true}"""
  doAssert parseFirstCallArgs(parsed, args)

  parsed.output.add(ResponseOutput(
    `type`: ResponseOutputKind.message,
    content: @[
      ResponseOutputPart(
        `type`: ResponseOutputPartType.refusal,
        refusal: "no"
      ),
      ResponseOutputPart(
        `type`: ResponseOutputPartType.output_text,
        text: ""
      ),
      ResponseOutputPart(
        `type`: ResponseOutputPartType.output_text,
        text: "later"
      )
    ]
  ))
  doAssert firstText(parsed) == "{\"answer\":42,\"future\":true}"
  doAssert outputText(parsed) == "{\"answer\":42,\"future\":true}later"
  outputItem(parsed, 2).content[2].text = "changed"
  doAssert outputItem(parsed, 2).content[2].text == "changed"

  var heterogeneous = parsed
  heterogeneous.output.delete(0)
  doAssert firstText(heterogeneous) == "changed"
  doAssert outputText(heterogeneous) == "changed"

  let futureItem = fromJson(
    """{"id":"future_1","type":"future_output_item","status":"completed"}""",
    ResponseOutput
  )
  doAssert futureItem.`type` == ResponseOutputKind.unknown

  let futureContent = fromJson(
    """{"type":"future_content","text":"future"}""",
    ResponseOutputPart
  )
  doAssert futureContent.`type` == ResponseOutputPartType.unknown

block parse_failure:
  var parsed: ResponseResult
  doAssert not responseParse("{bad json", parsed)

block missing_accessors:
  var parsed: ResponseResult
  doAssert responseParse(
    """{"id":"r","object":"response","created_at":1,"status":"in_progress",""" &
      """"model":"m","output":[],"usage":null}""",
    parsed
  )
  doAssertRaises ValueError:
    discard firstText(parsed)
  doAssertRaises ValueError:
    discard outputItem(parsed, 0)
  doAssert outputText(parsed) == ""
  doAssertRaises ValueError:
    discard firstCallId(parsed)
  doAssert not hasError(parsed)
  doAssertRaises ValueError:
    discard errorOf(parsed)
  doAssertRaises ValueError:
    discard inputTokens(parsed)

  var failed: ResponseResult
  doAssert responseParse(
    """{"id":"r","object":"response","created_at":1,"status":"failed",""" &
      """"model":"m","output":[],"error":{"code":"server_error","message":"bad"}}""",
    failed
  )
  doAssert hasError(failed)
  doAssert errorOf(failed).code == "server_error"
  doAssert errorOf(failed).message == "bad"
