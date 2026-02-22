import std/[base64, os, random, times]
import relay
import openai
import openai_retry

{.passL: "-lcurl".}

const
  ApiUrl = "https://api.deepinfra.com/v1/openai/chat/completions"
  ModelName = "allenai/olmOCR-2-7B-1025"

proc buildBase64ImageDataUrl(path: string): string =
  let imageBytes = readFile(path)
  result = "data:image/jpeg;base64," & encode(imageBytes)

proc runOcr(client: Relay; endpoint: OpenAIConfig; params: ChatCreateParams;
    retryPolicy: RetryPolicy): ChatCreateResult =
  var rng = initRand(seed = epochTime().int64)
  let maxAttempts = max(1, retryPolicy.maxAttempts)
  var done = false
  var lastError = "request failed without error details"
  for attempt in 1..maxAttempts:
    let req = chatRequest(
      cfg = endpoint,
      params = params,
      requestId = int64(attempt),
      timeoutMs = 120_000
    )

    let item = client.makeRequest(req)
    if item.error.kind != teNone:
      let canRetry = isRetriableTransport(item.error.kind) and attempt < maxAttempts
      if canRetry:
        sleep(retryDelayMs(rng, attempt, retryPolicy))
      else:
        lastError = "transport error kind=" & $item.error.kind &
          " message=" & item.error.message
    else:
      if isHttpSuccess(item.response.code):
        var parsed: ChatCreateResult
        if chatParse(item.response.body, parsed):
          result = parsed
          done = true
        else:
          raise newException(IOError, "JSON decode failed for successful OCR response")
      else:
        let canRetry = isRetriableStatus(item.response.code) and attempt < maxAttempts
        if canRetry:
          sleep(retryDelayMs(rng, attempt, retryPolicy))
        else:
          lastError = "http status error=" & $item.response.code &
            " body=" & item.response.body

    if done:
      break

  if not done:
    raise newException(IOError, "OCR request failed after retries: " & lastError)

proc main =
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  if apiKey.len == 0:
    raise newException(IOError,
      "DEEPINFRA_API_KEY is required. Export it (for example: set -a; source .env; set +a).")

  let localImagePath = "test.jpg"
  let imageDataUrl = buildBase64ImageDataUrl(localImagePath)

  let params = chatCreate(
    model = ModelName,
    messages = [
      userMessageParts([
        partText("Extract all readable text exactly."),
        partImageUrl(imageDataUrl)
      ])
    ],
    temperature = 0.0,
    maxTokens = 256,
    toolChoice = ToolChoice.none,
    responseFormat = formatText()
  )

  let endpoint = OpenAIConfig(
    url: ApiUrl,
    apiKey: apiKey
  )
  let retryPolicy = defaultRetryPolicy(
    maxAttempts = 5,
    baseDelayMs = RetryBaseDelayMs,
    maxDelayMs = RetryMaxDelayMs,
    jitterDivisor = RetryJitterDivisor
  )

  var client = newRelay(maxInFlight = 1, defaultTimeoutMs = 120_000)
  defer: client.close()

  let parsed = runOcr(client, endpoint, params, retryPolicy)
  echo "model=", modelOf(parsed)
  echo "choices=", choices(parsed)
  echo "assistant_text=", firstText(parsed)

when isMainModule:
  main()
