# openai (Nim)

OpenAI-style chat-completions helpers for Nim, built to work directly with
[`relay`](https://github.com/planetis-m/relay).

## Goals

- Keep Relay as the transport layer owner.
- Avoid wrapping or hiding Relay lifecycle/queue behavior.
- Provide ergonomic OpenAI-facing request builders and response accessors.
- Use direct-to-object JSON mapping (`jsonx`), not `std/json`.

## Install

This repo is structured for Atlas-style dependency management.

- Keep `nim.cfg` Atlas-managed.
- Use local `config.nims` files (`root`, `tests/`, `examples/`) for source paths.
- Build with direct `nim` commands.

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

## API Surface

### Request construction

- `OpenAIConfig(url, apiKey)`
- `chatCreate(...) -> ChatCreateParams`
- `chatRequest(cfg, params, ...) -> RequestSpec`
- `chatAdd(batch, cfg, params, ...)`
- `chatParse(body, dst) -> bool`

### Message/content helpers

- `systemMessageText`, `userMessageText`, `assistantMessageText`, `toolMessageText`
- `userMessageParts`
- `partText`, `partImageUrl`, `partInputAudio`
- `contentText`, `contentParts`
- `toolFunction`

### Response format constants

- `formatText`
- `formatJsonObject`
- `formatJsonSchema`
- `formatRegex`

### Response accessors

- `idOf`, `modelOf`
- `promptTokens`, `completionTokens`, `totalTokens`
- `choices`, `finish`, `firstText`, `allTextParts`
- `calls`, `firstCallName`, `firstCallArgs`

## Included runnable examples

- `examples/live_batch_chat_polling.nim`
- `examples/live_ocr_retry.nim`

Build with:

```bash
nim c examples/live_batch_chat_polling.nim
nim c examples/live_ocr_retry.nim
```

## Tests

```bash
nim c -r tests/test_openai.nim
nim c -r tests/test_openai_retry.nim
```
