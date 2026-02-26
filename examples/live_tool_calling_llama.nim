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

template firstToolCalls(x: ChatCreateResult): untyped =
  x.choices[0].message.tool_calls

template firstToolCall(x: ChatCreateResult): untyped =
  x.choices[0].message.tool_calls[0]

proc makeWeatherToolResult(args: WeatherToolArgs): string =
  let celsius = 9.0
  result = toJson(WeatherToolResult(
    city: args.city,
    temperatureC: celsius,
    condition: "light rain",
    windKph: 14.0,
    humidityPct: 82
  ))

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
  let firstTurn = requestChat(client, endpoint, params, requestId = 1)
  assert firstTurn.choices.len > 0, "No choices in first response."
  assert firstTurn.firstToolCalls.len > 0, firstText(firstTurn)

  # Run local tool code with model-provided arguments.
  let toolArgs = fromJson(
    firstTurn.firstToolCall.function.arguments,
    WeatherToolArgs
  )
  let toolResult = makeWeatherToolResult(toolArgs)
  echo "tool=", firstTurn.firstToolCall.function.name
  echo "args=", firstTurn.firstToolCall.function.arguments
  echo "toolResult=", toolResult

  # Turn 2: continue the same conversation with tool call + tool result.
  params.messages.add(ChatMessage(
    role: ChatMessageRole.assistant,
    tool_calls: firstTurn.firstToolCalls
  ))
  params.messages.add(toolMessageText(
    toolResult,
    firstTurn.firstToolCall.id,
    name = firstTurn.firstToolCall.function.name
  ))
  params.tool_choice = ToolChoice.none
  params.response_format = weatherAnswerFormat
  let secondTurn = requestChat(client, endpoint, params, requestId = 2)
  let answer = fromJson(firstText(secondTurn), WeatherAnswer)
  echo "model=", modelOf(secondTurn)
  echo "city=", answer.city
  echo "temperatureC=", answer.temperatureC
  echo "condition=", answer.condition
  echo "advice=", answer.advice

when isMainModule:
  main()
