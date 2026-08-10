## Helpers for creating and reading OpenAI Embeddings API requests.

import relay
import jsonx
import ./[config, http]
import ./schema/embeddings_schema

export config
export embeddings_schema

const EmbeddingsPath = "/embeddings"

proc inputText*(text: sink string): EmbeddingInput =
  ## Creates a single text input.
  EmbeddingInput(kind: EmbeddingInputKind.text, text: text)

proc inputTexts*(texts: sink seq[string]): EmbeddingInput =
  ## Creates a batch of text inputs.
  EmbeddingInput(kind: EmbeddingInputKind.texts, texts: texts)

proc inputTokens*(tokens: sink seq[int]): EmbeddingInput =
  ## Creates a single token-array input.
  EmbeddingInput(kind: EmbeddingInputKind.tokens, tokens: tokens)

proc inputTokenArrays*(tokenArrays: sink seq[seq[int]]): EmbeddingInput =
  ## Creates a batch of token-array inputs.
  EmbeddingInput(kind: EmbeddingInputKind.tokenArrays, token_arrays: tokenArrays)

proc embeddingCreate*(model: sink string; input: sink EmbeddingInput;
    encodingFormat = EmbeddingFormat.float; dimensions = 0;
    user: sink string = ""): EmbeddingParams =
  ## Creates parameters for `POST /embeddings`.
  EmbeddingParams(
    model: model,
    input: input,
    encoding_format: encodingFormat,
    dimensions: dimensions,
    user: user
  )

proc embeddingCreate*(model, input: sink string;
    encodingFormat = EmbeddingFormat.float; dimensions = 0;
    user: sink string = ""): EmbeddingParams =
  ## Creates parameters for a single text input.
  embeddingCreate(model, inputText(input), encodingFormat,
    dimensions, user)

proc embeddingRequest*(cfg: OpenAIConfig; params: EmbeddingParams;
    requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()): RequestSpec =
  request(cfg, hvPost, cfg.url & EmbeddingsPath, params,
    requestId, timeoutMs, headers)

proc embeddingAdd*(batch: var RequestBatch; cfg: OpenAIConfig;
    params: EmbeddingParams; requestId = 0'i64; timeoutMs = 0;
    headers: sink HttpHeaders = emptyHttpHeaders()) =
  requestAdd(batch, cfg, hvPost, cfg.url & EmbeddingsPath, params,
    requestId, timeoutMs, headers)

proc embeddingParse*(body: string; dst: out EmbeddingResult): bool =
  dst = default(EmbeddingResult)
  try:
    dst = fromJson(body, EmbeddingResult)
    result = true
  except CatchableError:
    result = false

proc raiseAccessorValueError(message: string) {.noinline, noreturn.} =
  raise newException(ValueError, message)

proc ensureEmbeddingIndex(embeddingCount, i: int) {.inline.} =
  if i < 0 or i >= embeddingCount:
    raiseAccessorValueError("vector index " & $i &
      " out of range for " & $embeddingCount & " embeddings")

proc ensureFloatEmbedding(x: EmbeddingValue; i: int) {.inline.} =
  if x.kind != EmbeddingValueKind.values:
    raiseAccessorValueError("vector " & $i &
      " uses base64 encoding; request float encoding or use vectorBase64()")

proc ensureBase64Embedding(x: EmbeddingValue; i: int) {.inline.} =
  if x.kind != EmbeddingValueKind.encoded:
    raiseAccessorValueError("vector " & $i &
      " uses float encoding; use vector() for numeric vectors")

proc vector*(x: EmbeddingResult; i = 0): lent seq[float32] {.inline.} =
  ensureEmbeddingIndex(x.data.len, i)
  ensureFloatEmbedding(x.data[i].embedding, i)
  result = x.data[i].embedding.values

proc vector*(x: var EmbeddingResult; i = 0): var seq[float32] {.inline.} =
  ensureEmbeddingIndex(x.data.len, i)
  ensureFloatEmbedding(x.data[i].embedding, i)
  result = x.data[i].embedding.values

proc vectorBase64*(x: EmbeddingResult; i = 0): lent string {.inline.} =
  ensureEmbeddingIndex(x.data.len, i)
  ensureBase64Embedding(x.data[i].embedding, i)
  result = x.data[i].embedding.encoded

proc vectorBase64*(x: var EmbeddingResult; i = 0): var string {.inline.} =
  ensureEmbeddingIndex(x.data.len, i)
  ensureBase64Embedding(x.data[i].embedding, i)
  result = x.data[i].embedding.encoded

proc inputTokens*(x: EmbeddingResult): int {.inline.} =
  result = x.usage.prompt_tokens

proc totalTokens*(x: EmbeddingResult): int {.inline.} =
  result = x.usage.total_tokens
