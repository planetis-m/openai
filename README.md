# openai (Nim)

An OpenAI-style Nim client that stays out of your transport layer.

This package gives you an ergonomic API for building chat-completions requests
and reading responses, while you keep full control of HTTP via
[`relay`](https://github.com/planetis-m/relay).

## Why Try This Client?

- Relay-native: reuse your existing `Relay` client, batching, and polling flow.
- OpenAI wording, Nim ergonomics: `chatCreate`, `userMessageText`,
  `partImageUrl`, `firstText`.
- Strongly typed JSON mapping via `jsonx` (no dynamic `std/json` trees).
- Optional retry helpers in `openai_retry`, so policy stays in your app.
- No hidden transport abstraction to fight when scaling or debugging.

## Install

Add this dependency to your project `.nimble` file:

```nim
requires "https://github.com/planetis-m/openai"
```

Then resolve dependencies with either:

```bash
atlas install
```

or:

```bash
nimble sync
```

## What Feels Different

Build requests with readable helpers:

```nim
let params = chatCreate(
  model = "gpt-4.1-mini",
  messages = @[
    systemMessageText("Be concise."),
    userMessageText("Explain retry jitter in one sentence.")
  ],
  temperature = 0.2,
  maxTokens = 64,
  toolChoice = ToolChoice.none,
  responseFormat = formatText
)
```

Send with Relay directly:

```nim
let item = client.makeRequest(chatRequest(cfg, params))
var parsed: ChatCreateResult
if item.error.kind == teNone and item.response.code == 200 and
    chatParse(item.response.body, parsed):
  echo "model=", modelOf(parsed)
  echo "text=", firstText(parsed)
  echo "tokens=", totalTokens(parsed)
```

Parse and access important fields quickly:

```nim
echo "model=", modelOf(parsed)
echo "text=", firstText(parsed)
echo "tokens=", totalTokens(parsed)
```

## Quick Start

```nim
import std/os
import relay, openai

{.passL: "-lcurl".}

const ApiUrl = "https://api.openai.com/v1/chat/completions"

proc main() =
  let cfg = OpenAIConfig(
    url: ApiUrl,
    apiKey: getEnv("OPENAI_API_KEY")
  )

  let params = chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("Write one short Nim tip.")],
    temperature = 0.2,
    maxTokens = 48,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

  let client = newRelay(maxInFlight = 1, defaultTimeoutMs = 30_000)
  defer: client.close()

  let item = client.makeRequest(chatRequest(cfg, params))
  var parsed: ChatCreateResult
  if item.error.kind == teNone and item.response.code == 200 and
      chatParse(item.response.body, parsed):
    echo "model=", modelOf(parsed)
    echo "text=", firstText(parsed)

main()
```

## Batch Polling Flow

```nim
import std/os
import relay, openai

{.passL: "-lcurl".}

const ApiUrl = "https://api.openai.com/v1/chat/completions"

proc main() =
  let cfg = OpenAIConfig(url: ApiUrl, apiKey: getEnv("OPENAI_API_KEY"))
  let client = newRelay(maxInFlight = 4, defaultTimeoutMs = 30_000)
  defer: client.close()

  var batch: RequestBatch
  chatAdd(batch, cfg, chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("Define gradient descent in one sentence.")]
  ), requestId = 1)
  chatAdd(batch, cfg, chatCreate(
    model = "gpt-4.1-mini",
    messages = @[userMessageText("Define dropout in one sentence.")]
  ), requestId = 2)

  # Capture size before startRequests(batch) moves the batch.
  var remaining = batch.len
  client.startRequests(batch)

  while remaining > 0:
    var item: RequestResult
    if client.waitForResult(item):
      var parsed: ChatCreateResult
      if item.error.kind == teNone and item.response.code == 200 and
          chatParse(item.response.body, parsed):
        echo item.response.request.requestId, ": ", firstText(parsed)
      dec remaining

main()
```

## Multimodal Message Parts

```nim
let params = chatCreate(
  model = "gpt-4.1-mini",
  messages = @[
    userMessageParts(@[
      partText("Describe this image."),
      partImageUrl("data:image/jpeg;base64,...")
    ])
  ],
  toolChoice = ToolChoice.none,
  responseFormat = formatText
)
```

## Schema-First Tool Calling + Structured Output

Define the shape once and get predictable results end-to-end: clean tool calls
in, clean structured answers out.

```nim
type
  SchemaProp = object
    `type`: string
    description: string

  WeatherToolSchema = object
    `type`: string
    properties: tuple[
      city: SchemaProp,
      unit: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  WeatherAnswerSchema = object
    `type`: string
    properties: tuple[
      summary: SchemaProp,
      celsius: SchemaProp,
      advice: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

let weatherTool = toolFunction(
  "get_weather",
  "Look up current weather for a city",
  WeatherToolSchema(
    `type`: "object",
    properties: (
      city: SchemaProp(`type`: "string", description: "City name"),
      unit: SchemaProp(`type`: "string", description: "celsius or fahrenheit")
    ),
    required: @["city"],
    additionalProperties: false
  )
)

let weatherOutput = formatJsonSchema(
  "weather_answer",
  WeatherAnswerSchema(
    `type`: "object",
    properties: (
      summary: SchemaProp(`type`: "string", description: "One-line weather summary"),
      celsius: SchemaProp(`type`: "number", description: "Current temperature in C"),
      advice: SchemaProp(`type`: "string", description: "Simple clothing advice")
    ),
    required: @["summary", "celsius", "advice"],
    additionalProperties: false
  ),
  strict = true
)

let params = chatCreate(
  model = "gpt-4.1-mini",
  messages = @[userMessageText("What's the weather in Berlin and what should I wear?")],
  tools = @[weatherTool],
  toolChoice = ToolChoice.required,
  responseFormat = weatherOutput
)
```

## Optional Retry Module

`openai_retry` is optional.

```nim
import std/[random, times]
import relay, openai, openai_retry

proc requestWithRetry(client: Relay; cfg: OpenAIConfig;
    params: ChatCreateParams): ChatCreateResult =
  let policy = defaultRetryPolicy(maxAttempts = 5)
  var rng = initRand(epochTime().int64)
  let maxAttempts = max(1, policy.maxAttempts)

  for attempt in 1..maxAttempts:
    let item = client.makeRequest(chatRequest(cfg, params, requestId = attempt.int64))
    discard chatParse(item.response.body, result)
    let canRetry = attempt < maxAttempts and
      (isRetriableTransport(item.error.kind) or isRetriableStatus(item.response.code))
    if canRetry:
      sleep(retryDelayMs(rng, attempt, policy))
    else:
      break
```

## API Cheat Sheet

- Request/config:
  `OpenAIConfig`, `chatCreate`, `chatRequest`, `chatAdd`, `chatParse`
- Message/content helpers:
  `systemMessageText`, `userMessageText`, `assistantMessageText`,
  `toolMessageText`, `userMessageParts`, `partText`, `partImageUrl`,
  `partInputAudio`, `contentText`, `contentParts`, `toolFunction`,
  `toolFunction(name, description, parametersSchema)`
- Response formats:
  `formatText`, `formatJsonObject`, `formatJsonSchema(name, schema, strict=true)`, `formatRegex`
- Response accessors:
  `idOf`, `modelOf`, `choices`, `finish`, `firstText`, `allTextParts`,
  `calls`, `firstCallName`, `firstCallArgs`, `promptTokens`,
  `completionTokens`, `totalTokens`
- Retry helpers:
  `defaultRetryPolicy`, `retryDelayMs`, `isRetriableStatus`,
  `isRetriableTransport` (from `openai_retry`)

## Run Examples

`DEEPINFRA_API_KEY` is required. Export it (for example: `set -a; source .env; set +a`).

```bash
nim c -r examples/live_batch_chat_polling.nim
nim c -r examples/live_ocr_retry.nim
```

## Run Tests

```bash
nim c -r tests/test_openai.nim
nim c -r tests/test_openai_retry.nim
```
