import std/strutils
import relay
import openai/files

const FileResponse = """{
  "id": "file-abc123",
  "object": "file",
  "bytes": 120000,
  "created_at": 1677610602,
  "expires_at": null,
  "filename": "mydata.jsonl",
  "purpose": "fine-tune",
  "status": "processed"
}"""

const FileListResponse = """{
  "object": "list",
  "data": [""" & FileResponse & """],
  "first_id": "file-abc123",
  "last_id": "file-abc456",
  "has_more": false
}"""

const FileDeletedResponse = """{
  "id": "file-abc123",
  "object": "file",
  "deleted": true
}"""

proc sampleConfig(apiKey = "sk-test"): OpenAIConfig =
  OpenAIConfig(
    url: OpenAIBaseUrl,
    apiKey: apiKey
  )

proc testFileUploadRequest() =
  let cfg = sampleConfig(apiKey = "new-token")
  var headers = emptyHttpHeaders()
  headers["Authorization"] = "Bearer old-token"
  headers["X-Trace-Id"] = "trace-1"

  let req = fileUploadRequest(
    cfg,
    filename = "input.jsonl",
    purpose = "batch",
    content = "{\"custom_id\":\"request-1\"}",
    boundary = "test-boundary",
    requestId = 7,
    timeoutMs = 60_000,
    headers = move headers
  )

  doAssert req.verb == hvPost
  doAssert req.url == cfg.url & "/files"
  doAssert req.requestId == 7
  doAssert req.timeoutMs == 60_000
  doAssert req.headers["Authorization"] == "Bearer new-token"
  doAssert req.headers["Content-Type"] == "multipart/form-data; boundary=test-boundary"
  doAssert req.headers["X-Trace-Id"] == "trace-1"
  doAssert req.body.contains("name=\"purpose\"")
  doAssert req.body.contains("batch")
  doAssert req.body.contains("name=\"file\"; filename=\"input.jsonl\"")
  doAssert req.body.contains("Content-Type: application/json")
  doAssert req.body.contains("{\"custom_id\":\"request-1\"}")
  doAssert req.body.endsWith("--test-boundary--\r\n")

proc testFileRequestBuilders() =
  let cfg = sampleConfig()

  let retrieve = fileRetrieveRequest(cfg, "file-abc123", requestId = 1)
  doAssert retrieve.verb == hvGet
  doAssert retrieve.url == cfg.url & "/files/file-abc123"
  doAssert retrieve.body.len == 0

  let list = fileListRequest(cfg, after = "file-abc", purpose = "batch", limit = 10)
  doAssert list.verb == hvGet
  doAssert list.url == cfg.url & "/files?after=file-abc&purpose=batch&limit=10"

  let plainList = fileListRequest(cfg)
  doAssert plainList.url == cfg.url & "/files"

  let content = fileContentRequest(cfg, "file-abc123")
  doAssert content.verb == hvGet
  doAssert content.url == cfg.url & "/files/file-abc123/content"

  let delete = fileDeleteRequest(cfg, "file-abc123")
  doAssert delete.verb == hvDelete
  doAssert delete.url == cfg.url & "/files/file-abc123"

  let fake = OpenAIConfig(url: "http://localhost:9000/v1", apiKey: "sk-test")
  doAssert fileRetrieveRequest(fake, "file-abc123").url ==
    "http://localhost:9000/v1/files/file-abc123"

proc testFileParseAndAccessors() =
  var file: FileInfo
  doAssert fileParse(FileResponse, file)
  doAssert file.id == "file-abc123"
  doAssert file.purpose == FilePurpose.fine_tune
  doAssert file.bytes == 120000
  doAssert expiresAt(file) == 0
  doAssert not fileParse("{bad", file)
  doAssert file == default(FileInfo)
  doAssert not fileParse("{}", file)
  doAssert file == default(FileInfo)

  var list: FilePage
  doAssert fileListParse(FileListResponse, list)
  doAssert list.data.len == 1
  doAssert not list.has_more

  var deleted: DeletedFile
  doAssert fileDeletedParse(FileDeletedResponse, deleted)
  doAssert deleted.deleted

proc testFilePurposeStringValues() =
  doAssert $FilePurpose.fine_tune == "fine-tune"
  doAssert $FilePurpose.fine_tune_results == "fine-tune-results"
  doAssert $FilePurpose.batch == "batch"
  doAssert parseEnum[FilePurpose]("fine-tune-results") == FilePurpose.fine_tune_results

proc testFileUploadAdd() =
  let cfg = sampleConfig()
  var batch: RequestBatch
  fileUploadAdd(batch, cfg, "input.jsonl", "batch",
    "{\"custom_id\":\"request-1\"}", boundary = "b1", requestId = 9, timeoutMs = 5000)

  doAssert batch.len == 1
  doAssert batch[0].verb == hvPost
  doAssert batch[0].requestId == 9
  doAssert batch[0].timeoutMs == 5000
  doAssert batch[0].headers["Content-Type"] == "multipart/form-data; boundary=b1"
  doAssert batch[0].body.contains("--b1--\r\n")

when isMainModule:
  testFileUploadRequest()
  testFileRequestBuilders()
  testFileParseAndAccessors()
  testFilePurposeStringValues()
  testFileUploadAdd()
