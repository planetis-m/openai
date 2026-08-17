import std/strutils
import relay
import jsonx
import jsonx/streams
import openai/batch

const CompletedBatchResponse = """{
  "id": "batch_abc123",
  "object": "batch",
  "endpoint": "/v1/chat/completions",
  "errors": null,
  "input_file_id": "file-abc123",
  "completion_window": "24h",
  "status": "completed",
  "output_file_id": "file-cvaTdG",
  "error_file_id": "file-HOWS94",
  "created_at": 1711471533,
  "in_progress_at": 1711471538,
  "expires_at": 1711557933,
  "finalizing_at": 1711493133,
  "completed_at": 1711493163,
  "failed_at": null,
  "expired_at": null,
  "cancelling_at": null,
  "cancelled_at": null,
  "request_counts": {
    "total": 100,
    "completed": 95,
    "failed": 5
  },
  "usage": {
    "input_tokens": 1000,
    "input_tokens_details": {"cached_tokens": 960},
    "output_tokens": 200,
    "output_tokens_details": {"reasoning_tokens": 0},
    "total_tokens": 1200
  },
  "metadata": {
    "customer_id": "user_123456789"
  }
}"""

const ValidatingBatchResponse = """{
  "id": "batch_xyz789",
  "object": "batch",
  "endpoint": "/v1/chat/completions",
  "errors": null,
  "input_file_id": "file-abc123",
  "completion_window": "24h",
  "status": "validating",
  "created_at": 1711471533
}"""

const FailedBatchResponse = """{
  "id": "batch_fail1",
  "object": "batch",
  "endpoint": "/v1/chat/completions",
  "input_file_id": "file-abc123",
  "completion_window": "24h",
  "status": "failed",
  "created_at": 1711471533,
  "failed_at": 1711472133,
  "errors": {
    "object": "list",
    "data": [
      {"code": "invalid_json", "line": 3, "message": "bad line", "param": null}
    ]
  }
}"""

const BatchListResponse = """{
  "object": "list",
  "data": [""" & CompletedBatchResponse & """],
  "first_id": "batch_abc123",
  "last_id": "batch_abc456",
  "has_more": true
}"""

const OutputLineSuccess = """{"id":"batch_req_123","custom_id":"request-2","response":{"status_code":200,"request_id":"req_123","body":{"id":"chatcmpl-123","object":"chat.completion","created":1711652795,"model":"gpt-5.6-luna","choices":[{"index":0,"message":{"role":"assistant","content":"Hello."},"finish_reason":"stop"}],"usage":{"prompt_tokens":22,"completion_tokens":2,"total_tokens":24}}},"error":null}"""

const OutputLineError = """{"id":"batch_req_123","custom_id":"request-3","response":null,"error":{"code":"batch_expired","message":"This request could not be executed before the completion window expired."}}"""

proc sampleConfig(apiKey = "sk-test"): OpenAIConfig =
  OpenAIConfig(
    url: OpenAIBaseUrl,
    apiKey: apiKey
  )

proc testBatchCreate() =
  let params = batchCreate(
    inputFileId = "file-abc123",
    endpoint = "/v1/chat/completions"
  )
  doAssert toJson(params) ==
    """{"input_file_id":"file-abc123","endpoint":"/v1/chat/completions","completion_window":"24h"}"""

  let withMetadata = batchCreate(
    inputFileId = "file-abc123",
    endpoint = "/v1/chat/completions",
    metadata = RawJson("""{"run":"r1"}""")
  )
  doAssert toJson(withMetadata) ==
    """{"input_file_id":"file-abc123","endpoint":"/v1/chat/completions","completion_window":"24h","metadata":{"run":"r1"}}"""

  let withExpiry = batchCreate(
    inputFileId = "file-abc123",
    endpoint = "/v1/chat/completions",
    metadata = RawJson("""{"run":"r1"}"""),
    outputExpiresAfter = outputExpiry(2592000)
  )
  doAssert toJson(withExpiry) ==
    """{"input_file_id":"file-abc123","endpoint":"/v1/chat/completions","completion_window":"24h","metadata":{"run":"r1"},"output_expires_after":{"anchor":"created_at","seconds":2592000}}"""

proc testBatchRequestBuilders() =
  let cfg = sampleConfig()

  let create = batchCreateRequest(cfg, batchCreate("file-abc123",
    "/v1/chat/completions"), requestId = 2)
  doAssert create.verb == hvPost
  doAssert create.url == cfg.url & "/batches"
  doAssert create.body ==
    """{"input_file_id":"file-abc123","endpoint":"/v1/chat/completions","completion_window":"24h"}"""

  let retrieve = batchRetrieveRequest(cfg, "batch_abc123")
  doAssert retrieve.verb == hvGet
  doAssert retrieve.url == cfg.url & "/batches/batch_abc123"

  let list = batchListRequest(cfg, after = "batch_abc", limit = 20)
  doAssert list.verb == hvGet
  doAssert list.url == cfg.url & "/batches?after=batch_abc&limit=20"

  let cancel = batchCancelRequest(cfg, "batch_abc123")
  doAssert cancel.verb == hvPost
  doAssert cancel.url == cfg.url & "/batches/batch_abc123/cancel"
  doAssert cancel.body.len == 0

proc testInputLineJson() =
  let line = inputLineJson(
    "request-1",
    RawJson("""{"model":"gpt-5.6-luna","messages":[{"role":"user","content":"hi"}]}"""),
    url = "/v1/chat/completions",
  )
  doAssert line ==
    """{"custom_id":"request-1","method":"POST","url":"/v1/chat/completions","body":{"model":"gpt-5.6-luna","messages":[{"role":"user","content":"hi"}]}}""" & "\n"

  var st = streams.open("")
  addInputLine(st, "request-1",
    RawJson("""{"model":"gpt-5.6-luna","messages":[{"role":"user","content":"hi"}]}"""),
    "/v1/chat/completions")
  doAssert move(st.s) == line

  let parsed = fromJson(line, BatchInputLine)
  doAssert parsed.custom_id == "request-1"
  doAssert parsed.`method` == "POST"
  doAssert parsed.url == "/v1/chat/completions"
  doAssert string(parsed.body).contains("gpt-5.6-luna")

  let obj = inputLine("request-1",
    RawJson("""{"model":"gpt-5.6-luna"}"""), "/v1/chat/completions")
  doAssert obj.custom_id == "request-1"
  doAssert obj.`method` == "POST"
  doAssert obj.url == "/v1/chat/completions"

proc testBatchParseAndAccessors() =
  var parsed: Batch
  doAssert batchParse(CompletedBatchResponse, parsed)
  doAssert parsed.id == "batch_abc123"
  doAssert parsed.status == BatchStatus.completed
  doAssert isTerminal(parsed)
  doAssert not hasModel(parsed)
  doAssert inputFileId(parsed) == "file-abc123"
  doAssert hasOutputFile(parsed)
  doAssert outputFileId(parsed) == "file-cvaTdG"
  doAssert hasErrorFile(parsed)
  doAssert errorFileId(parsed) == "file-HOWS94"
  doAssert hasRequestCounts(parsed)
  doAssert requestCountsOf(parsed).total == 100
  doAssert totalRequests(parsed) == 100
  doAssert completedRequests(parsed) == 95
  doAssert failedRequests(parsed) == 5
  doAssert inputTokens(parsed) == 1000
  doAssert outputTokens(parsed) == 200
  doAssert totalTokens(parsed) == 1200
  doAssert hasUsage(parsed)
  doAssert usageOf(parsed).input_tokens_details.cached_tokens == 960
  doAssert usageOf(parsed).output_tokens_details.reasoning_tokens == 0
  doAssert cachedInputTokens(parsed) == 960
  doAssert reasoningTokens(parsed) == 0
  doAssert completedAt(parsed) == 1711493163
  doAssert failedAt(parsed) == 0
  doAssert not isFailed(parsed)
  doAssert not isExpired(parsed)
  doAssert not isCancelled(parsed)
  doAssert errorCount(parsed) == 0
  doAssert hasMetadata(parsed)
  doAssert ($metadataOf(parsed)).contains("customer_id")

  var validating: Batch
  doAssert batchParse(ValidatingBatchResponse, validating)
  doAssert validating.status == BatchStatus.validating
  doAssert not isTerminal(validating)
  doAssert not hasMetadata(validating)
  doAssert not hasRequestCounts(validating)
  doAssert not hasUsage(validating)
  doAssertRaises ValueError:
    discard requestCountsOf(validating)
  doAssertRaises ValueError:
    discard totalRequests(validating)
  doAssertRaises ValueError:
    discard inputTokens(validating)
  doAssertRaises ValueError:
    discard totalTokens(validating)
  doAssertRaises ValueError:
    discard usageOf(validating)

  var failed: Batch
  doAssert batchParse(FailedBatchResponse, failed)
  doAssert isFailed(failed)
  doAssert failedAt(failed) == 1711472133
  doAssert errorCount(failed) == 1
  doAssert failed.errors.isSome
  doAssert failed.errors.get.data[0].code == "invalid_json"
  doAssert lineOf(failed.errors.get.data[0]) == 3

proc testBatchParseFailure() =
  var parsed: Batch
  doAssert not batchParse("{bad json", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.input_file_id.len == 0
  doAssert not batchParse("{}", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.input_file_id.len == 0

proc testBatchListParse() =
  var parsed: BatchList
  doAssert batchListParse(BatchListResponse, parsed)
  doAssert parsed.data.len == 1
  doAssert parsed.has_more
  doAssert parsed.first_id == "batch_abc123"
  doAssert parsed.data[0].id == "batch_abc123"

proc testOutputLineParse() =
  var ok: BatchOutputLine
  doAssert batchOutputLineParse(OutputLineSuccess, ok)
  doAssert ok.custom_id == "request-2"
  doAssert ok.response.isSome
  doAssert ok.error.isNone
  doAssert hasOutputResponse(ok)
  doAssert not hasOutputError(ok)
  doAssert outputResponseOf(ok).request_id == "req_123"
  doAssert outputStatusCode(ok) == 200
  doAssert outputRequestId(ok) == "req_123"
  doAssert ($outputBody(ok)).contains("chatcmpl-123")
  doAssert ($outputBody(ok)).contains("gpt-5.6-luna")

  var err: BatchOutputLine
  doAssert batchOutputLineParse(OutputLineError, err)
  doAssert err.custom_id == "request-3"
  doAssert err.response.isNone
  doAssert err.error.isSome
  doAssert not hasOutputResponse(err)
  doAssert hasOutputError(err)
  doAssert outputErrorOf(err).code == "batch_expired"
  doAssert outputErrorCode(err) == "batch_expired"
  doAssert outputErrorMessage(err).contains("completion window")

when isMainModule:
  testBatchCreate()
  testBatchRequestBuilders()
  testInputLineJson()
  testBatchParseAndAccessors()
  testBatchParseFailure()
  testBatchListParse()
  testOutputLineParse()
