# openai (Nim)

An OpenAI API client for Nim that stays out of your transport layer.

Build Responses, Chat Completions, embeddings, speech, file, and batch requests
with typed Nim values while keeping full control of HTTP via
[`relay`](https://github.com/planetis-m/relay).

## Why Try This Client?

- Relay-native: reuse your existing `Relay` client, batching, and polling flow.
- OpenAI wording, Nim ergonomics: `responseCreate`, `chatCreate`,
  `inputText`, `userMessageText`, `firstText`.
- Strongly typed JSON mapping via `jsonx` (no dynamic `std/json` trees).
- Optional retry helpers in `relay/retry`, so policy stays in your app.
- No hidden transport abstraction to fight when scaling or debugging.

## Install

Add this dependency to your project `.nimble` file:

```nim
requires "https://github.com/planetis-m/openai"
```

Then resolve dependencies with Atlas:

```bash
atlas install
```

## Importing

`import openai` provides shared configuration and error-envelope decoding only. Import each capability
explicitly; this keeps focused helper names such as `partText` unambiguous:

```nim
import openai            # OpenAIConfig, OpenAIBaseUrl, and OpenAIErrorResponse
import openai/responses  # Responses API only
import openai/chat       # chat completions only
import openai/batch      # batch API only
```

When importing two capability modules with overlapping helper names, qualify
the call: `chat.partText("hello")` or `responses.partText("hello")`.

Retry policy helpers live in `relay/retry` and status classifiers in `relay/http_status`; they are not part of the OpenAI API surface.

## Configuration

`OpenAIConfig` holds the API key and the API **base** URL; every request
builder derives its endpoint from `cfg.url`:

```nim
OpenAIConfig(apiKey: getEnv("OPENAI_API_KEY"))          # https://api.openai.com/v1
OpenAIConfig(apiKey: key, url: "https://api.deepinfra.com/v1/openai")
```

`organization` and `project`, when set, are sent as `OpenAI-Organization` /
`OpenAI-Project` headers.

## What Feels Different

Build requests with readable helpers:

```nim
import openai/chat

let params = chatCreate(
  model = "gpt-4.1-mini",
  messages = @[
    systemMessageText("Be concise."),
    userMessageText("Explain retry jitter in one sentence.")
  ],
  temperature = 0.2,
  maxCompletionTokens = 64,
  toolChoice = ChatToolChoiceNone,
  responseFormat = formatText
)
```

Send with Relay directly:

```nim
let item = client.makeRequest(chatRequest(cfg, params))
var parsed: ChatResult
if item.error.kind == teNone and item.response.code == Http200 and
    chatParse(item.response.body, parsed):
  echo "model=", parsed.model
  echo "text=", firstText(parsed)
  echo "tokens=", totalTokens(parsed)
```

Parse and access important fields quickly:

```nim
echo "model=", parsed.model
echo "text=", firstText(parsed)
echo "tokens=", totalTokens(parsed)
```

## Quick Start: Responses API

```nim
import std/os
import relay
import openai/responses

{.passL: "-lcurl".}

proc main() =
  let cfg = OpenAIConfig(apiKey: getEnv("OPENAI_API_KEY"))

  let params = responseCreate(
    model = "gpt-5.6-luna",
    input = inputText("Write one short Nim tip."),
    maxOutputTokens = 48
  )

  let client = newRelay(maxInFlight = 1, defaultTimeoutMs = 30_000)
  defer: client.close()

  let item = client.makeRequest(responseRequest(cfg, params))
  var parsed: ResponseResult
  if item.error.kind == teNone and item.response.code == Http200 and
      responseParse(item.response.body, parsed):
    echo "model=", parsed.model
    echo "text=", firstText(parsed)

main()
```

The Responses constructors intentionally omit deprecated request fields.

## Relay Request Batching

```nim
import std/os
import relay
import openai/chat

{.passL: "-lcurl".}

proc main() =
  let cfg = OpenAIConfig(apiKey: getEnv("OPENAI_API_KEY"))
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
      var parsed: ChatResult
      if item.error.kind == teNone and item.response.code == Http200 and
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
  toolChoice = ChatToolChoiceNone,
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

let weatherTool = functionTool(
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
  messages = @[
    userMessageText("What's the weather in Berlin and what should I wear?")
  ],
  tools = @[weatherTool],
  toolChoice = ChatToolChoiceRequired,
  responseFormat = weatherOutput
)
```

## Files API Module

`openai/files` covers the Files API, a general resource used by fine-tuning,
vision, and Batch. Upload a JSONL input file with
`purpose = "batch"` (multipart is built for you), then list, retrieve,
download, or delete files:

```nim
let upload = fileUploadRequest(cfg, "input.jsonl", "batch", jsonlContent)
var uploaded: FileInfo
if fileParse(client.makeRequest(upload).response.body, uploaded):
  echo "file=", uploaded.id

let download = fileContentRequest(cfg, "file-abc123")
let content = client.makeRequest(download).response.body
```

## Batch API Module

`openai/batch` covers the Batches API used by asynchronous workloads: create
and poll a batch from an uploaded request file, then collect and reconcile
the output lines by `custom_id`.

```nim
import jsonx
import openai/[batch, chat]

proc main() =
  # One JSONL request line per chat-completions call.
  let params = chatCreate(
    model = "gpt-5.6-luna",
    messages = @[userMessageText("Define batch polling in one sentence.")]
  )
  let line = inputLineJson(
    "request-1",
    RawJson(toJson(params)),
    url = "/v1/chat/completions"
  )
  echo line

main()
```

Create a batch from an uploaded input file, poll it by status, then read the
output and error files:

```nim
let create = batchCreateRequest(cfg,
  batchCreate("file-abc123", "/v1/chat/completions"))
var batch: Batch
if batchParse(client.makeRequest(create).response.body, batch):
  echo "batch=", batch.id, " status=", batch.status

let retrieve = batchRetrieveRequest(cfg, batch.id)
if batchParse(client.makeRequest(retrieve).response.body, batch):
  if batch.status == BatchStatus.completed:
    echo "output=", outputFileId(batch)
    echo "usage=", inputTokens(batch), "/", outputTokens(batch)
```

Statuses cover `validating`, `failed`, `in_progress`, `finalizing`,
`completed`, `expired`, `cancelling`, and `cancelled`; `isTerminal` reports
whether a batch can no longer progress. Parse each line of a downloaded
output/error file with `batchOutputLineParse` and map results back to requests
by `custom_id` (`outputStatusCode`, `outputRequestId`, `outputBody`,
`outputErrorCode`).

## Compatible and Strict JSON Decoding

Response parsers skip unknown object fields so additions to the API do not
break existing clients. For fixture validation or an exact schema, decode the
public schema type with jsonx directly:

```nim
import jsonx
import openai/responses

var parsed: ResponseResult
discard responseParse(body, parsed)
let strict = fromJson(body, ResponseResult, unknownFields = ufReject)
```

Custom schema decoders forward the selected policy through nested decoded values.

## Optional Retry Module

`relay/retry` is optional.

```nim
import std/[random, times]
import relay
import openai/chat

proc requestWithRetry(client: Relay; cfg: OpenAIConfig;
    params: ChatParams): ChatResult =
  let policy = initRetryPolicy(maxAttempts = 5)
  var rng = initRand(epochTime().int64)
  let maxAttempts = max(1, policy.maxAttempts)

  for attempt in 1..maxAttempts:
    let item = client.makeRequest(chatRequest(cfg, params, requestId = attempt.int64))
    discard chatParse(item.response.body, result)
    let canRetry = attempt < maxAttempts and
      (isRetryable(item.error.kind) or isRetryable(item.response.code))
    if canRetry:
      sleep(retryDelayMs(rng, attempt, policy))
    else:
      break
```

## API Cheat Sheet

- Responses API:
  `inputText`, `inputItems`, `responseCreate`,
  `responseRequest`, `responseAdd`, `responseParse`, `functionTool`,
  `formatJsonSchema`, `functionOutputJson`
- Chat Completions:
  `chatCreate`, `chatRequest`, `chatAdd`, `chatParse`,
  `systemMessageText`, `developerMessageText`,
  `userMessageText`, `userMessageParts`, `partText`,
  `partImageUrl`, `functionTool`, `formatJsonSchema`
- Shared response accessors:
  `createdAt`, `firstText`, `allTextParts`, `functionCalls`,
  `firstCallId`, `firstCallName`, `firstCallArgs`, `parseFirstTextJson`,
  `parseFirstCallArgs`, `inputTokens`, `outputTokens`, `totalTokens`
  - Chat accessors select a completion with `i = 0`.
  - Responses text and function-call accessors scan the heterogeneous output list in response
    order. Use `outputItem(response, outputIndex)` for explicit positional access.
  - `allTextParts` concatenates all text parts into one string.
- Prompt caching:
  `PromptCacheMode`, `PromptCacheTtl`, `PromptCacheOptions`
- Embeddings:
  `inputText`, `inputTexts`, `inputTokens`,
  `embeddingCreate`, `embeddingRequest`, `embeddingAdd`, `embeddingParse`,
  `vector`, `vectorBase64`
- Speech:
  `voice`, `customVoice`, `speechCreate`, `speechRequest`,
  `speechAdd`
- Retry helpers:
  `initRetryPolicy`, `retryDelayMs`, `isRetryable` (from `relay/retry`)
- Batch helpers (from `openai/batch`):
  `batchCreate`, `batchCreateRequest`, `batchRetrieveRequest`,
  `batchListRequest`, `batchCancelRequest`, `batchParse`, `batchListParse`,
  `inputLine`, `inputLineJson`, `addInputLine`, `batchOutputLineParse`,
  `isTerminal`, `totalRequests`, `inputTokens`, `outputTokens`
- File helpers (from `openai/files`):
  `fileUploadRequest`, `fileUploadAdd`, `fileRetrieveRequest`,
  `fileListRequest`, `fileContentRequest`, `fileDeleteRequest`,
  `fileParse`, `fileListParse`, `fileDeletedParse`

## Run Examples

`DEEPINFRA_API_KEY` is required. Export it (for example: `set -a; source .env; set +a`).

```bash
nim c -r examples/live_batch_chat_polling.nim
nim c -r examples/live_ocr_retry.nim
nim c -r examples/live_tool_calling_llama.nim
```

## Run Tests

```bash
nim c -r tests/tester.nim
```

The tester auto-discovers every `t*.nim` file under `tests/`. Run all
configurations with `nim c -d:release -r tests/tester.nim` and
`nim c -d:danger -r tests/tester.nim`.
