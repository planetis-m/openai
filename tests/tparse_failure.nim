import openai/[batch, chat, embeddings, error, files, responses]

type
  ParsedText = object
    text: string
    count: int

  ParsedArgs = object
    q: string

block error_parse_failure_leaves_default:
  var parsed: OpenAIErrorResponse
  doAssert not errorParse("not json", parsed)
  doAssert parsed.error.message.len == 0
  doAssert parsed.error.code.isNone
  doAssert parsed.error.param.isNone

block batch_parse_failure_leaves_default:
  var parsed: Batch
  doAssert not batchParse("{", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.input_file_id.len == 0
  doAssert parsed.status == BatchStatus.validating

block batch_parse_missing_id_fails:
  var parsed: Batch
  doAssert not batchParse("""{"id":"","status":"expired"}""", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.status == BatchStatus.expired
  doAssert not batchParse("{", parsed)
  doAssert parsed.status == BatchStatus.validating

block batch_list_parse_failure_leaves_default:
  var parsed: BatchList
  doAssert not batchListParse("[", parsed)
  doAssert parsed.data.len == 0
  doAssert not parsed.has_more

block batch_output_line_parse_failure_leaves_default:
  var parsed: BatchOutputLine
  doAssert not batchOutputLineParse("}", parsed)
  doAssert parsed.id.len == 0
  doAssert not hasOutputResponse(parsed)
  doAssert not hasOutputError(parsed)

block chat_parse_failure_leaves_default:
  var parsed: ChatResult
  doAssert not chatParse("", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.choices.len == 0
  doAssert parsed.model.len == 0

block chat_parse_first_text_json_failure_leaves_default:
  var parsed: ChatResult
  doAssert chatParse(
    """{"id":"c","model":"m","choices":[{"index":0,"message":{"role":"assistant","tool_calls":[],"content":"not json"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}""",
    parsed)
  var dst: ParsedText
  doAssert not parseFirstTextJson(parsed, dst)
  doAssert dst.text.len == 0
  doAssert dst.count == 0

block chat_parse_first_call_args_failure_leaves_default:
  var parsed: ChatResult
  doAssert chatParse(
    """{"id":"c","model":"m","choices":[{"index":0,"message":{"role":"assistant","tool_calls":[],"content":"text"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}""",
    parsed)
  var dst: ParsedArgs
  doAssert not parseFirstCallArgs(parsed, dst)
  doAssert dst.q.len == 0

block embedding_parse_failure_leaves_default:
  var parsed: EmbeddingResult
  doAssert not embeddingParse("nope", parsed)
  doAssert parsed.data.len == 0
  doAssert parsed.`object`.len == 0
  doAssert inputTokens(parsed) == 0
  doAssert totalTokens(parsed) == 0

block file_parse_failure_leaves_default:
  var parsed: FileInfo
  doAssert not fileParse("{", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.filename.len == 0
  doAssert parsed.expires_at.isNone

block file_parse_missing_id_fails:
  var parsed: FileInfo
  doAssert not fileParse("""{"id":"","filename":"a.json"}""", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.filename == "a.json"
  doAssert not fileParse("{", parsed)
  doAssert parsed.filename.len == 0

block file_list_parse_failure_leaves_default:
  var parsed: FilePage
  doAssert not fileListParse("x", parsed)
  doAssert parsed.data.len == 0
  doAssert not parsed.has_more

block file_deleted_parse_failure_leaves_default:
  var parsed: DeletedFile
  doAssert not fileDeletedParse("x", parsed)
  doAssert parsed.id.len == 0
  doAssert not parsed.deleted

block response_parse_failure_leaves_default:
  var parsed: ResponseResult
  doAssert not responseParse("", parsed)
  doAssert parsed.id.len == 0
  doAssert parsed.output.len == 0
  doAssert parsed.model.len == 0

block response_parse_first_text_json_failure_leaves_default:
  var parsed: ResponseResult
  doAssert responseParse(
    """{"id":"r","output":[{"type":"message","content":[{"type":"output_text","text":"no json here"}]}]}""",
    parsed)
  var dst: ParsedText
  doAssert not parseFirstTextJson(parsed, dst)
  doAssert dst.text.len == 0
  doAssert dst.count == 0

block response_parse_first_call_args_failure_leaves_default:
  var parsed: ResponseResult
  doAssert responseParse("""{"id":"r","output":[]}""", parsed)
  var dst: ParsedArgs
  doAssert not parseFirstCallArgs(parsed, dst)
  doAssert dst.q.len == 0
