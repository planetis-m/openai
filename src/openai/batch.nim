## Helpers for creating and reading OpenAI Batch API requests and JSONL files.

import relay
import jsonx
import jsonx/streams
import ./[config, http]
import ./schema/batch_schema

export config
export batch_schema

const
  BatchesPath = "/batches"

proc batchCreate*(inputFileId, endpoint: sink string;
    metadata: sink RawJson = RawJson("");
    outputExpiresAfter = BatchOutputExpiry()): BatchParams {.inline.} =
  result = BatchParams(
    input_file_id: inputFileId,
    endpoint: endpoint,
    metadata: metadata,
    output_expires_after: outputExpiresAfter
  )

proc outputExpiry*(seconds: int;
    anchor: sink string = "created_at"): BatchOutputExpiry {.inline.} =
  BatchOutputExpiry(anchor: anchor, seconds: seconds)

proc batchCreateRequest*(cfg: OpenAIConfig; params: BatchParams;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvPost, cfg.url & BatchesPath, params, requestId, timeoutMs, headers)

proc batchRetrieveRequest*(cfg: OpenAIConfig; batchId: string;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvGet, cfg.url & BatchesPath & "/" & batchId, requestId, timeoutMs, headers)

proc batchListRequest*(cfg: OpenAIConfig; after = ""; limit = 0;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  var params = emptyQueryParams()
  if after.len > 0:
    params["after"] = after
  if limit > 0:
    params["limit"] = $limit
  request(cfg, hvGet, cfg.url & BatchesPath & queryString(params),
    requestId, timeoutMs, headers)

proc batchCancelRequest*(cfg: OpenAIConfig; batchId: string;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvPost, cfg.url & BatchesPath & "/" & batchId & "/cancel",
    requestId, timeoutMs, headers)

proc inputLine*(customId: sink string; body: sink RawJson;
    url: string): BatchInputLine =
  BatchInputLine(custom_id: customId, url: url, body: body)

proc addInputLine*(s: Stream; customId: sink string;
    body: sink RawJson; url: string) =
  writeJson(s, inputLine(customId, body, url))
  s.write('\n')

proc inputLineJson*(customId: sink string; body: sink RawJson; url: string): string =
  let s = streams.open(newStringOfCap(string(body).len + 200))
  addInputLine(s, customId, body, url)
  result = move(s.s)

proc batchParse*(body: string; dst: out Batch): bool =
  try:
    dst = fromJson(body, Batch)
    result = dst.id.len > 0
  except CatchableError:
    dst = default(Batch)
    result = false

proc batchListParse*(body: string; dst: out BatchList): bool =
  try:
    dst = fromJson(body, BatchList)
    result = true
  except CatchableError:
    dst = default(BatchList)
    result = false

proc batchOutputLineParse*(line: string; dst: out BatchOutputLine): bool =
  try:
    dst = fromJson(line, BatchOutputLine)
    result = true
  except CatchableError:
    dst = default(BatchOutputLine)
    result = false

proc isTerminal*(x: Batch): bool {.inline.} =
  result = x.status in {BatchStatus.completed, failed, expired, cancelled}

proc isFailed*(x: Batch): bool {.inline.} =
  result = x.status == BatchStatus.failed

proc isExpired*(x: Batch): bool {.inline.} =
  result = x.status == BatchStatus.expired

proc isCancelled*(x: Batch): bool {.inline.} =
  result = x.status == BatchStatus.cancelled

proc createdAt*(x: Batch): int64 {.inline.} =
  result = int64(x.created_at)

proc inProgressAt*(x: Batch): int64 {.inline.} =
  result = x.in_progress_at.get(0)

proc finalizingAt*(x: Batch): int64 {.inline.} =
  result = x.finalizing_at.get(0)

proc completedAt*(x: Batch): int64 {.inline.} =
  result = x.completed_at.get(0)

proc failedAt*(x: Batch): int64 {.inline.} =
  result = x.failed_at.get(0)

proc expiredAt*(x: Batch): int64 {.inline.} =
  result = x.expired_at.get(0)

proc expiresAt*(x: Batch): int64 {.inline.} =
  result = x.expires_at.get(0)

proc cancellingAt*(x: Batch): int64 {.inline.} =
  result = x.cancelling_at.get(0)

proc cancelledAt*(x: Batch): int64 {.inline.} =
  result = x.cancelled_at.get(0)

proc errorCount*(x: Batch): int {.inline.} =
  result = x.errors.get(BatchErrorList()).data.len

proc raiseBatchAccessorError(message: string) {.noinline, noreturn.} =
  raise newException(ValueError, message)

proc lineOf*(x: BatchError): int {.inline.} =
  result = x.line.get(0)

proc hasModel*(x: Batch): bool {.inline.} =
  x.model.isSome

proc modelOf*(x: Batch): lent string =
  if x.model.isNone:
    raiseBatchAccessorError("batch has no model")
  result = x.model.get

proc inputFileId*(x: Batch): lent string {.inline.} =
  result = x.input_file_id

proc hasOutputFile*(x: Batch): bool {.inline.} =
  x.output_file_id.isSome

proc outputFileId*(x: Batch): lent string =
  if x.output_file_id.isNone:
    raiseBatchAccessorError("batch has no output file")
  result = x.output_file_id.get

proc hasErrorFile*(x: Batch): bool {.inline.} =
  x.error_file_id.isSome

proc errorFileId*(x: Batch): lent string =
  if x.error_file_id.isNone:
    raiseBatchAccessorError("batch has no error file")
  result = x.error_file_id.get

proc hasMetadata*(x: Batch): bool {.inline.} =
  x.metadata.isSome

proc metadataOf*(x: Batch): lent RawJson =
  if x.metadata.isNone:
    raiseBatchAccessorError("batch has no metadata")
  result = x.metadata.get

proc hasRequestCounts*(x: Batch): bool {.inline.} =
  x.request_counts.isSome

proc requestCountsOf*(x: Batch): lent BatchCounts {.inline.} =
  if x.request_counts.isNone:
    raiseBatchAccessorError("batch has no request counts")
  result = x.request_counts.get

proc totalRequests*(x: Batch): int {.inline.} =
  x.requestCountsOf().total

proc completedRequests*(x: Batch): int {.inline.} =
  x.requestCountsOf().completed

proc failedRequests*(x: Batch): int {.inline.} =
  x.requestCountsOf().failed

proc hasUsage*(x: Batch): bool {.inline.} =
  x.usage.isSome

proc usageOf*(x: Batch): lent BatchUsage {.inline.} =
  if x.usage.isNone:
    raiseBatchAccessorError("batch has no usage data")
  result = x.usage.get

proc inputTokens*(x: Batch): int {.inline.} =
  x.usageOf().input_tokens

proc cachedInputTokens*(x: Batch): int {.inline.} =
  x.usageOf().input_tokens_details.cached_tokens

proc outputTokens*(x: Batch): int {.inline.} =
  x.usageOf().output_tokens

proc reasoningTokens*(x: Batch): int {.inline.} =
  x.usageOf().output_tokens_details.reasoning_tokens

proc totalTokens*(x: Batch): int {.inline.} =
  x.usageOf().total_tokens

proc hasOutputResponse*(x: BatchOutputLine): bool {.inline.} =
  x.response.isSome

proc outputResponseOf*(x: BatchOutputLine): lent BatchOutputResponse {.inline.} =
  if x.response.isNone:
    raiseBatchAccessorError("batch output line has no response")
  result = x.response.get

proc hasOutputError*(x: BatchOutputLine): bool {.inline.} =
  x.error.isSome

proc outputErrorOf*(x: BatchOutputLine): lent BatchOutputError {.inline.} =
  if x.error.isNone:
    raiseBatchAccessorError("batch output line has no error")
  result = x.error.get

proc outputStatusCode*(x: BatchOutputLine): int {.inline.} =
  result = x.outputResponseOf().status_code

proc outputRequestId*(x: BatchOutputLine): lent string {.inline.} =
  result = x.outputResponseOf().request_id

proc outputBody*(x: BatchOutputLine): lent RawJson {.inline.} =
  result = x.outputResponseOf().body

proc outputErrorCode*(x: BatchOutputLine): lent string {.inline.} =
  result = x.outputErrorOf().code

proc outputErrorMessage*(x: BatchOutputLine): lent string {.inline.} =
  result = x.outputErrorOf().message
