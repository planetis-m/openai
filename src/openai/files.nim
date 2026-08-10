import std/strutils
import relay
import jsonx
import ./[config, http]
import ./schema/files_schema

export config
export files_schema

const
  FilesPath = "/files"
  DefaultMultipartBoundary* = "openai-nim-batch"

proc uploadBody*(filename, purpose, content, boundary: string): string =
  result = "--" & boundary & "\r\n" &
    "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n" &
    purpose & "\r\n" &
    "--" & boundary & "\r\n" &
    "Content-Disposition: form-data; name=\"file\"; filename=\"" & filename & "\"\r\n" &
    "Content-Type: application/json\r\n\r\n" &
    content & "\r\n" &
    "--" & boundary & "--\r\n"

proc fileUploadRequest*(cfg: OpenAIConfig; filename, purpose: string;
    content: sink string; boundary = DefaultMultipartBoundary;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  var hs = cfg.withDefaultHeaders(headers)
  hs["Content-Type"] = "multipart/form-data; boundary=" & boundary
  result = RequestSpec(
    verb: hvPost,
    url: cfg.url & FilesPath,
    headers: hs,
    body: uploadBody(filename, purpose, content, boundary),
    requestId: requestId,
    timeoutMs: timeoutMs
  )

proc fileUploadAdd*(batch: var RequestBatch; cfg: OpenAIConfig;
    filename, purpose: string; content: sink string;
    boundary = DefaultMultipartBoundary;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  var hs = cfg.withDefaultHeaders(headers)
  hs["Content-Type"] = "multipart/form-data; boundary=" & boundary
  batch.addRequest(
    verb = hvPost,
    url = cfg.url & FilesPath,
    headers = hs,
    body = uploadBody(filename, purpose, content, boundary),
    requestId = requestId,
    timeoutMs = timeoutMs
  )

proc fileRetrieveRequest*(cfg: OpenAIConfig; fileId: string;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvGet, cfg.url & FilesPath & "/" & fileId,
    requestId, timeoutMs, headers)

proc fileListRequest*(cfg: OpenAIConfig; after = ""; purpose = ""; limit = 0;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  var params: QueryParams
  if after.len > 0:
    params["after"] = after
  if purpose.len > 0:
    params["purpose"] = purpose
  if limit > 0:
    params["limit"] = $limit
  request(cfg, hvGet, cfg.url & FilesPath & queryString(params),
    requestId, timeoutMs, headers)

proc fileContentRequest*(cfg: OpenAIConfig; fileId: string;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvGet, cfg.url & FilesPath & "/" & fileId & "/content",
    requestId, timeoutMs, headers)

proc fileDeleteRequest*(cfg: OpenAIConfig; fileId: string;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvDelete, cfg.url & FilesPath & "/" & fileId,
    requestId, timeoutMs, headers)

proc fileParse*(body: string; dst: out FileInfo): bool =
  dst = default(FileInfo)
  try:
    dst = fromJson(body, FileInfo)
    result = dst.id.len > 0
  except CatchableError:
    result = false

proc fileListParse*(body: string; dst: out FilePage): bool =
  dst = default(FilePage)
  try:
    dst = fromJson(body, FilePage)
    result = true
  except CatchableError:
    result = false

proc fileDeletedParse*(body: string; dst: out DeletedFile): bool =
  dst = default(DeletedFile)
  try:
    dst = fromJson(body, DeletedFile)
    result = true
  except CatchableError:
    result = false

proc expiresAt*(x: FileInfo): int64 {.inline.} =
  result = x.expires_at.get(0)
