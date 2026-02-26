import std/os
import jsonx, relay, openai

{.passL: "-lcurl".}

const
  RequestTimeoutMs = 30_000

type
  SchemaProp = object
    `type`: string
    description: string

  WeatherToolSchema = object
    `type`: string
    properties: tuple[city: SchemaProp]
    required: seq[string]
    additionalProperties: bool

  WeatherToolArgs = object
    city: string

  WeatherToolResult = object
    city: string
    temperatureC: float
    condition: string
    windKph: float
    humidityPct: int

  WeatherAnswerSchema = object
    `type`: string
    properties: tuple[
      city: SchemaProp,
      temperatureC: SchemaProp,
      condition: SchemaProp,
      advice: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  WeatherAnswer = object
    city: string
    temperatureC: float
    condition: string
    advice: string

proc makeWeatherToolResult(args: WeatherToolArgs): WeatherToolResult =
  let celsius = 9.0
  result = WeatherToolResult(
    city: args.city,
    temperatureC: celsius,
    condition: "light rain",
    windKph: 14.0,
    humidityPct: 82
  )

proc requestChat(client: Relay; endpoint: OpenAIConfig; params: ChatCreateParams;
    requestId: int64): ChatCreateResult =
  let item = client.makeRequest(chatRequest(
    cfg = endpoint,
    params = params,
    requestId = requestId,
    timeoutMs = RequestTimeoutMs
  ))
  discard chatParse(item.response.body, result)
  echo "requestId=", requestId,
    " status=", item.response.code,
    " error=", item.error.kind

proc main() =
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  if apiKey.len == 0:
    quit("Set DEEPINFRA_API_KEY before running this example.")

  let weatherTool = toolFunction(
    "get_weather",
    "Look up current weather for a city.",
    WeatherToolSchema(
      `type`: "object",
      properties: (city: SchemaProp(`type`: "string", description: "City name")),
      required: @["city"],
      additionalProperties: false
    )
  )
  let weatherAnswerFormat = formatJsonSchema(
    "weather_answer",
    WeatherAnswerSchema(
      `type`: "object",
      properties: (
        city: SchemaProp(`type`: "string", description: "City name"),
        temperatureC: SchemaProp(`type`: "number", description: "Temperature in Celsius"),
        condition: SchemaProp(`type`: "string", description: "Weather condition"),
        advice: SchemaProp(`type`: "string", description: "What to wear")
      ),
      required: @["city", "temperatureC", "condition", "advice"],
      additionalProperties: false
    ),
    strict = true
  )
  let endpoint = OpenAIConfig(
    url: "https://api.deepinfra.com/v1/openai/chat/completions",
    apiKey: apiKey
  )
  let client = newRelay(maxInFlight = 1, defaultTimeoutMs = RequestTimeoutMs)
  defer: client.close()

  # Turn 1: force a tool call.
  var params = chatCreate(
    model = "Qwen/Qwen3-235B-A22B-Instruct-2507",
    messages = @[
      systemMessageText("You are concise. Use the weather tool before answering weather questions."),
      userMessageText("What is the weather in Seattle today and what should I wear?")
    ],
    temperature = 0.0,
    maxTokens = 128,
    tools = @[weatherTool],
    toolChoice = ToolChoice.required,
    responseFormat = formatText
  )

  # Run local tool code with model-provided arguments.
  let firstTurn = requestChat(client, endpoint, params, requestId = 1)
  var toolArgs: WeatherToolArgs
  doAssert parseFirstCallArgs(firstTurn, toolArgs), firstCallArgs(firstTurn)
  let toolResult = makeWeatherToolResult(toolArgs)
  echo "\n[Tool Execution]",
    "\n  Tool:        ", firstCallName(firstTurn),
    "\n  Arguments:   ", firstCallArgs(firstTurn),
    "\n  Result:      ", toJson(toolResult)

  # Turn 2: continue the same conversation with tool call + tool result.
  params.messages.add(assistantMessageToolCalls(calls(firstTurn)))
  params.messages.add(toolMessageJson(
    toolResult,
    firstCallId(firstTurn),
    name = firstCallName(firstTurn)
  ))
  params.tool_choice = ToolChoice.none
  params.response_format = weatherAnswerFormat

  let secondTurn = requestChat(client, endpoint, params, requestId = 2)
  var answer: WeatherAnswer
  doAssert parseFirstTextJson(secondTurn, answer), firstText(secondTurn)
  echo "\n[Weather Information]",
    "\n  Model:       ", modelOf(secondTurn),
    "\n  City:        ", answer.city,
    "\n  Temperature: ", answer.temperatureC, "°C",
    "\n  Condition:   ", answer.condition,
    "\n  Advice:      ", answer.advice

when isMainModule:
  main()
