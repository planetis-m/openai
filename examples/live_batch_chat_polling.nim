import std/[os, strutils]
import relay
import openai

{.passL: "-lcurl".}

const
  ApiUrl = "https://api.deepinfra.com/v1/openai/chat/completions"
  ModelName = "mistralai/Mistral-Nemo-Instruct-2407"
  TotalRequests = 12
  RequestsPerBatch = 3
  MaxQueuedOrInFlight = 6
  RequestTimeoutMs = 30_000

proc buildParams(prompt: string): ChatCreateParams =
  chatCreate(
    model = ModelName,
    messages = [userMessageText(prompt)],
    temperature = 0.0,
    maxTokens = 48,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

proc printCompletion(item: RequestResult) =
  var parsed: ChatCreateResult
  discard chatParse(item.response.body, parsed)
  echo "completed id=", item.response.request.requestId,
    " status=", item.response.code,
    " error=", item.error.kind,
    " text=\"", firstText(parsed), "\""

proc main() =
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  let endpoint = OpenAIConfig(
    url: ApiUrl,
    apiKey: apiKey
  )

  var client = newRelay(maxInFlight = 4, defaultTimeoutMs = RequestTimeoutMs, maxRedirects = 5)
  defer: client.close()

  let prompts = [
    "Give a one-line definition of convolution in CNNs.",
    "Give a one-line definition of max pooling.",
    "Give a one-line definition of a fully connected layer."
  ]

  var submitted = 0
  var completed = 0
  var nextRequestId = 1'i64

  while completed < TotalRequests:
    let queuedOrInFlight = client.queueLen() + client.numInFlight()
    if submitted < TotalRequests and queuedOrInFlight < MaxQueuedOrInFlight:
      var batch: RequestBatch
      var added = 0
      while added < RequestsPerBatch and submitted < TotalRequests:
        let prompt = prompts[submitted mod prompts.len]
        let params = buildParams(prompt)

        chatAdd(
          batch = batch,
          cfg = endpoint,
          params = params,
          requestId = nextRequestId,
          timeoutMs = RequestTimeoutMs
        )

        inc nextRequestId
        inc submitted
        inc added

      client.startRequests(batch)
      echo "submitted batchSize=", added, " totalSubmitted=", submitted

    var item: RequestResult
    if client.pollForResult(item):
      inc completed
      printCompletion(item)
    else:
      sleep(10)

  echo "done submitted=", submitted, " completed=", completed

when isMainModule:
  main()
