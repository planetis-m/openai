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
  messages = [
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
```

Parse and access important fields quickly:

```nim
var parsed: ChatCreateResult
discard chatParse(item.response.body, parsed)
echo "model=", modelOf(parsed)
echo "text=", firstText(parsed)
echo "tokens=", totalTokens(parsed)
```

## Quick Start

```nim
import std/os
import relay
import openai

{.passL: "-lcurl".}

const ApiUrl = "https://api.openai.com/v1/chat/completions"

proc main() =
  let cfg = OpenAIConfig(
    url: ApiUrl,
    apiKey: getEnv("OPENAI_API_KEY")
  )

  let params = chatCreate(
    model = "gpt-4.1-mini",
    messages = [userMessageText("Write one short Nim tip.")],
    temperature = 0.2,
    maxTokens = 48,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

  var client = newRelay(maxInFlight = 1, defaultTimeoutMs = 30_000)
  defer: client.close()

  let item = client.makeRequest(chatRequest(cfg, params))
  var parsed: ChatCreateResult
  discard chatParse(item.response.body, parsed)

  echo "model=", modelOf(parsed)
  echo "text=", firstText(parsed)

when isMainModule:
  main()
```

## Batch Polling Flow

```nim
import std/os
import relay
import openai

{.passL: "-lcurl".}

const ApiUrl = "https://api.openai.com/v1/chat/completions"

proc main() =
  let cfg = OpenAIConfig(url: ApiUrl, apiKey: getEnv("OPENAI_API_KEY"))
  var client = newRelay(maxInFlight = 4, defaultTimeoutMs = 30_000)
  defer: client.close()

  var batch: RequestBatch
  chatAdd(batch, cfg, chatCreate(
    model = "gpt-4.1-mini",
    messages = [userMessageText("Define gradient descent in one sentence.")]
  ), requestId = 1)
  chatAdd(batch, cfg, chatCreate(
    model = "gpt-4.1-mini",
    messages = [userMessageText("Define dropout in one sentence.")]
  ), requestId = 2)

  client.startRequests(batch)

  var remaining = batch.len
  while remaining > 0:
    var item: RequestResult
    if client.waitForResult(item):
      var parsed: ChatCreateResult
      discard chatParse(item.response.body, parsed)
      echo item.response.request.requestId, ": ", firstText(parsed)
      dec remaining

when isMainModule:
  main()
```

## Multimodal Message Parts

```nim
let params = chatCreate(
  model = "gpt-4.1-mini",
  messages = [
    userMessageParts([
      partText("Describe this image."),
      partImageUrl("data:image/jpeg;base64,...")
    ])
  ],
  toolChoice = ToolChoice.none,
  responseFormat = formatText
)
```

## Optional Retry Module

`openai_retry` is optional and transport-agnostic.

```nim
import std/[random, times]
import relay
import openai
import openai_retry

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
  `partInputAudio`, `contentText`, `contentParts`, `toolFunction`
- Response formats:
  `formatText`, `formatJsonObject`, `formatJsonSchema`, `formatRegex`
- Response accessors:
  `idOf`, `modelOf`, `choices`, `finish`, `firstText`, `allTextParts`,
  `calls`, `firstCallName`, `firstCallArgs`, `promptTokens`,
  `completionTokens`, `totalTokens`

## Run Examples

```bash
nim c examples/live_batch_chat_polling.nim
nim c examples/live_ocr_retry.nim
```

## Run Tests

```bash
nim c -r tests/test_openai.nim
nim c -r tests/test_openai_retry.nim
```
