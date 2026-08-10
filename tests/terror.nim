import openai/error

block parse_envelope:
  var parsed: OpenAIErrorResponse
  doAssert errorParse(
    """{"request_id":"req_1","error":{"message":"Model busy, retry later","type":"invalid_request_error","param":null,"code":"engine_overloaded","future":true}}""",
    parsed)
  doAssert errorOf(parsed).code.get == "engine_overloaded"
  doAssert errorOf(parsed).param.isNone
  doAssert errorOf(parsed).`type` == "invalid_request_error"
  doAssert errorOf(parsed).message == "Model busy, retry later"

block parse_absent_error_field:
  var parsed: OpenAIErrorResponse
  doAssert not errorParse("""{"unrelated":true}""", parsed)

block parse_rejects_garbage:
  var parsed: OpenAIErrorResponse
  doAssert not errorParse("not json", parsed)

block accessors_mask_optional_fields:
  var parsed: OpenAIErrorResponse
  doAssert errorParse(
    """{"error":{"message":"bad","type":"invalid_request_error","param":null,"code":null}}""",
    parsed)
  let err = errorOf(parsed)
  doAssert not err.hasCode
  doAssert not err.hasParam
  doAssertRaises ValueError:
    discard err.codeOf
  doAssertRaises ValueError:
    discard err.paramOf

  var full: OpenAIErrorResponse
  doAssert errorParse(
    """{"error":{"message":"bad","type":"invalid_request_error","param":"temperature","code":"unsupported_value"}}""",
    full)
  doAssert errorOf(full).hasCode
  doAssert errorOf(full).codeOf == "unsupported_value"
  doAssert errorOf(full).hasParam
  doAssert errorOf(full).paramOf == "temperature"
