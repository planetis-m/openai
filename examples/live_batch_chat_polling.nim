import std/[os, strutils]
import relay
import ../openai

{.passL: "-lcurl".}

const
  ApiUrl = "https://api.deepinfra.com/v1/openai/chat/completions"
  ModelName = "mistralai/Mistral-Nemo-Instruct-2407"
  TotalRequests = 12
  RequestsPerBatch = 3
  MaxQueuedOrInFlight = 6
  RequestTimeoutMs = 30_000

proc summarizeText(text: string; maxLen = 80): string =
  let oneLine = text.replace("\n", " ").strip()
  if oneLine.len > maxLen:
    result = oneLine[0 ..< maxLen] & "..."
  else:
    result = oneLine

proc main() =
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  if apiKey.len == 0:
    raise newException(IOError,
      "DEEPINFRA_API_KEY is required. Export it (for example: set -a; source .env; set +a).")

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
        let params = chatCreate(
          model = ModelName,
          messages = [userMessageText(prompt)],
          temperature = 0.0,
          maxTokens = 48,
          toolChoice = ToolChoice.none,
          responseFormat = formatText()
        )

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
      let reqId = item.response.request.requestId

      if item.error.kind != teNone:
        echo "completed id=", reqId, " transportError=", item.error.kind
      else:
        if isHttpSuccess(item.response.code):
          var parsed: ChatCreateResult
          if chatParse(item.response.body, parsed):
            echo "completed id=", reqId,
              " status=", item.response.code,
              " text=\"", summarizeText(firstText(parsed)), "\""
          else:
            echo "completed id=", reqId,
              " status=", item.response.code,
              " parseError=true"
        else:
          echo "completed id=", reqId, " status=", item.response.code
    else:
      sleep(10)

  echo "done submitted=", submitted, " completed=", completed

when isMainModule:
  main()
