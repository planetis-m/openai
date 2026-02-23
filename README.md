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
var out: ChatCreateResult
discard chatParse(item.response.body, out)
echo "model=", modelOf(out)
echo "text=", firstText(out)
echo "tokens=", totalTokens(out)
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
    messages = [userMessageText("Give one Nim productivity tip.")],
    temperature = 0.2,
    maxTokens = 48,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

  var client = newRelay(maxInFlight = 1, defaultTimeoutMs = 30_000)
  defer: client.close()

  let item = client.makeRequest(chatRequest(cfg, params))
  var out: ChatCreateResult
  discard chatParse(item.response.body, out)
  echo firstText(out)

when isMainModule:
  main()
```

## Batching and Polling

Relay returns results in completion order. This library keeps that model intact:

```nim
var batch: RequestBatch
chatAdd(batch, cfg, chatCreate(
  model = "gpt-4.1-mini",
  messages = [userMessageText("Define SGD in one sentence.")]
), requestId = 1)
chatAdd(batch, cfg, chatCreate(
  model = "gpt-4.1-mini",
  messages = [userMessageText("Define Adam optimizer in one sentence.")]
), requestId = 2)

client.startRequests(batch)
```

## Multimodal and Tooling

```nim
let multimodal = chatCreate(
  model = "gpt-4.1-mini",
  messages = [
    userMessageParts([
      partText("Describe the image."),
      partImageUrl("data:image/jpeg;base64,...")
    ])
  ],
  tools = [toolFunction("extractFields", "Extract structured fields from text")],
  toolChoice = ToolChoice.auto,
  responseFormat = formatText
)
```

## Optional Retry Policy

Import `openai_retry` only when you want built-in backoff helpers:

```nim
import std/[random, times]
import openai_retry

let policy = defaultRetryPolicy(maxAttempts = 5)
var rng = initRand(epochTime().int64)
let delayMs = retryDelayMs(rng, attempt = 2, policy = policy)
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
