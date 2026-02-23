import std/[base64, os, random, strutils, times]
import relay
import openai
import openai_retry

{.passL: "-lcurl".}

const
  ApiUrl = "https://api.deepinfra.com/v1/openai/chat/completions"
  ModelName = "allenai/olmOCR-2-7B-1025"
  ImagePath = "examples/test.jpg"
  OcrInstruction = "Extract all readable text exactly."
  RequestTimeoutMs = 120_000

proc imageAsDataUrl(path: string): string =
  let imageBytes = readFile(path)
  result = "data:image/jpeg;base64," & encode(imageBytes)

proc buildOcrParams(imageDataUrl: string): ChatCreateParams =
  chatCreate(
    model = ModelName,
    messages = @[
      userMessageParts(@[
        partText(OcrInstruction),
        partImageUrl(imageDataUrl)
      ])
    ],
    temperature = 0.0,
    maxTokens = 256,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

proc shouldRetry(item: RequestResult; attempt: int; maxAttempts: int): bool =
  let hasMoreAttempts = attempt < maxAttempts
  let retryTransport = item.error.kind != teNone and
    isRetriableTransport(item.error.kind)
  let retryHttpStatus = item.error.kind == teNone and
    isRetriableStatus(item.response.code)
  result = hasMoreAttempts and (retryTransport or retryHttpStatus)

proc requestWithRetry(client: Relay; endpoint: OpenAIConfig; params: ChatCreateParams;
    retryPolicy: RetryPolicy): ChatCreateResult =
  var rng = initRand(seed = epochTime().int64)
  let maxAttempts = max(1, retryPolicy.maxAttempts)
  for attempt in 1..maxAttempts:
    let requestSpec = chatRequest(
      cfg = endpoint,
      params = params,
      requestId = int64(attempt),
      timeoutMs = RequestTimeoutMs
    )

    let item = client.makeRequest(requestSpec)
    discard chatParse(item.response.body, result)
    echo "attempt=", attempt,
      " status=", item.response.code,
      " error=", item.error.kind

    let canRetry = shouldRetry(item, attempt, maxAttempts)
    if canRetry:
      sleep(retryDelayMs(rng, attempt, retryPolicy))
    else:
      break

proc main() =
  let apiKey = getEnv("DEEPINFRA_API_KEY")

  let imageDataUrl = imageAsDataUrl(ImagePath)
  let params = buildOcrParams(imageDataUrl)

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

  var client = newRelay(maxInFlight = 1, defaultTimeoutMs = RequestTimeoutMs)
  defer: client.close()

  let parsed = requestWithRetry(client, endpoint, params, retryPolicy)
  echo "model=", modelOf(parsed)
  echo firstText(parsed).strip()

when isMainModule:
  main()
