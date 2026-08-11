# Repository Guidelines

These rules describe the public API and implementation style of this OpenAI client. Apply them to
new capabilities and when cleaning up existing modules. Prefer a coherent library-wide API over
preserving an accidental inconsistency; breaking changes are allowed when they make the public
contract materially clearer. Call out any such change in the handoff.

## Project Structure

- `src/openai.nim` is the lightweight package entry point. It exports shared configuration and
  error-envelope decoding only; callers import capability modules explicitly.
- `src/openai/<capability>.nim` owns the ergonomic API for one OpenAI capability: constructors,
  request builders, batch integration, parsers, and response accessors.
- `src/openai/schema/<capability>_schema.nim` owns direct JSON-mapped request and response types.
  Keep wire field names in `snake_case` so their relationship to the JSON is obvious.
- `src/openai/config.nim` owns shared client configuration.
- `src/openai/http.nim` owns the small shared layer over Relay for headers and request creation.
  Do not hide Relay behind another transport abstraction.
- `src/openai/error.nim` owns OpenAI error-envelope decoding and accessors.
- Retry policy and HTTP-status classification belong to `relay`, not this package.
- `tests/` contains standalone executable tests. `tests/tester.nim` discovers every `t*.nim`.
- `examples/` contains runnable examples.
- `nim.cfg` is Atlas-managed. Never edit it by hand.

## Public API Shape

- Use plain public `object` types for request and response data. Use `ref object` only when identity,
  aliasing, or shared lifetime is genuinely part of the contract.
- Give semantic values named public types. Do not introduce private `*Wire` objects merely to get a
  desired JSON shape when the public schema type can represent that shape directly.
- Schema types are the public request and result types directly: use concise names such as
  `ChatParams`, `ChatResult`, `ResponseParams`, and `ResponseResult`. Do not add type aliases.
- Keep the operation vocabulary uniform across capabilities:
  - `<capability>Create` constructs parameters.
  - `<capability>Request` creates a Relay request.
  - `<capability>Add` adds that request to a `RequestBatch`.
  - `<capability>Parse` decodes a response body into caller-owned storage and returns `bool`.
- Keep these high-frequency operation names capability-qualified even in a scoped module, for example
  `chatCreate` and `responseParse`. Focused typed builders drop the capability prefix: use names such
  as `partText`, `messageText`, `functionTool`, and `formatJsonSchema`. Ambiguity between two imported
  capability modules is intentional; callers qualify the occasional collision with the module name.
- Use the same accessor names for normalized or derived concepts: `createdAt`, `inputTokens`,
  `outputTokens`, `cachedInputTokens`, `reasoningTokens`, and `totalTokens`. Use direct field syntax
  for public wire fields such as `id`, `model`, and `status`.
- Export useful semantic accessors such as `outputResponseOf` and `outputErrorOf`. Keep only validation,
  serialization, and orchestration helpers private.
- Prefer procs and explicit variant objects over methods, runtime dispatch, converters, or clever
  templates. Templates are appropriate for small local serialization mechanics such as writing an
  object field.
- Use `sink T` for constructor inputs that are stored in the result. Call sink parameters normally;
  do not add `move` without a demonstrated ownership need.
- Use `openArray[T]` only for read-only traversal that should accept arrays and sequences. Use `seq[T]`
  where ownership, replacement, or resizing is part of the operation.

## Schema Types and Wire Literals

- Model a closed set of protocol strings with an enum, not `string`. This includes roles, item types,
  content types, modes, formats, statuses, and other documented literal sets.
- Give enum members explicit string values when the Nim identifier cannot or should not exactly match
  the wire spelling. The enum must round-trip through `$` and `parseEnum`.
- For an omittable request enum, use an `unspecified = ""` member when the empty value cannot be a valid
  wire value. The writer omits `unspecified`; it must not serialize it as an API value.
- If the service owns an evolving output enum and forward compatibility matters, add an `unknown = ""`
  member and a focused tolerant `readJson` overload that maps unrecognized strings to `unknown`.
  Request enums should remain strict so callers cannot construct invalid requests.
- Use jsonx's generic enum decoder for ordinary enums. Do not write a large per-enum `case` decoder
  unless the type deliberately has nonstandard compatibility behavior.
- Share a protocol type between Chat and Responses when the wire contract is the same. Do not create
  capability-prefixed duplicates that imply a distinction the API does not have.
- Keep genuinely open or arbitrary JSON as `RawJson`, including user-provided JSON Schema documents,
  metadata, and intentionally unmodelled extension payloads. Offer generic helper overloads that
  serialize typed Nim values once when that improves ergonomics.
- JSON Schema itself remains `RawJson`; do not attempt to model the entire JSON Schema language as a
  closed Nim object hierarchy.
- Do not retain deprecated OpenAI request fields. Implement the current API vocabulary and migration
  target instead of exposing both old and new fields.
- Do not expose a request parameter for a protocol value that has only one supported value. Encode the
  fixed value in the writer; add a typed enum only when the API documents multiple supported choices.

## Unions, Null, and Optionality

- Represent JSON unions with a discriminated object when callers need to distinguish their shapes.
  Examples include string-or-parts content and string-or-item-list input.
- If `null` is one legitimate arm of such a union, represent it with a `none` discriminator when that
  produces a clearer value API than wrapping the entire union in `Option[T]`. Chat assistant content
  is the reference pattern: `none`, `text`, or `parts`.
- Use `Option[T]` in direct response schemas when the server can actually return `null` or omit a value
  and preserving that distinction matters during decoding.
- Do not apply `Option[T]` mechanically to every optional request field. Prefer an omission sentinel
  and a custom writer when the wire domain has an unambiguous unused value:
  - `""` for omitted strings and `RawJson`
  - an empty sequence for omitted lists
  - `0` for omitted positive counts or timestamps
  - a documented enum `unspecified` member
  - the documented server default for fields such as `temperature`, `top_p`, `store`, or
    `parallel_tool_calls`, with the writer emitting only a non-default override
- Use `Option[T]` for a request only when omitted, `null`, and a concrete value have different API
  meanings, or when no sound sentinel exists.
- Do not expose an `Option[T]` from a convenience accessor merely because the schema stores one.
  Prefer `hasX` plus a strict `x`/`xOf` accessor that raises a clear `ValueError` when absent.
- A scalar accessor may return a documented sentinel such as `0` only when that value cannot be a
  valid result and the library consistently treats it as absence. Do not silently default values
  such as token or request counts where zero is meaningful; expose `hasX` plus a strict accessor.

## JSON Writing

- Request writers must express omission deliberately. Do not rely on a generic object serializer
  when it would send unwanted defaults or `null` fields.
- Always emit required fields. Emit optional fields only when their value differs from the chosen
  omission sentinel or documented server default.
- Serialize a value exactly once. Code such as `RawJson(toJson(toJson(value)))` is always wrong: the
  second conversion encodes JSON text as a JSON string. Use `RawJson(toJson(value))` when converting a
  typed value into an embedded raw JSON value.
- Prefer public typed request objects over ad hoc `RawJson` construction for stable protocol shapes
  such as messages, content parts, function outputs, tools, and named tool choices.
- A custom writer should branch on the discriminant and emit only fields valid for that variant.
  It should not leak inactive object fields into the payload.
- Keep required fallback schemas explicit, such as the empty object schema used when function
  parameters are absent.

## JSON Reading and Compatibility

- jsonx decoding skips unknown object fields by default with `ufSkip`. This is the normal production
  behavior and provides forward compatibility.
- Public parse helpers always use `ufSkip`. For fixture or schema validation, callers decode the
  public schema type directly with `fromJson(..., unknownFields = ufReject)`.
- The selected policy must propagate through nested objects, sequences, options, tables, references,
  tuples, files, and JSON iterators.
- Every custom `readJson` overload must accept `unknownFields: UnknownFieldPolicy` and forward it to
  nested `readJson` calls.
- Do not write large object-field dispatch decoders solely to skip unknown fields. Let jsonx decode
  ordinary objects. Keep a custom decoder only for a real union, a tolerant evolving enum, an unusual
  envelope, or another shape generic decoding cannot express correctly.
- Known fields remain type-checked in both policies. Malformed JSON must always fail.
- Public `<capability>Parse` helpers return `false` for JSON parsing failure and leave exception-based
  detail inside the decoding boundary. Do not catch defects or unrelated operational failures.

## Constructors and Raw JSON Helpers

- Constructors must build public schema values directly. Avoid parallel representations that can
  drift apart.
- Prefer focused helpers such as `partText`, `messageParts`, or
  `functionOutputJson` when they remove protocol boilerplate or prevent an invalid shape.
- Use typed content containers rather than returning `RawJson` for a stable message or content
  union. Use `RawJson` only at an intentionally open boundary.
- For schema-taking helpers, provide a `RawJson` overload and, where useful, a generic overload that
  calls `toJson` once. The generic overload should delegate to the canonical typed constructor.
- Do not add an accessor or constructor that merely mirrors public field syntax without improving
  validity, ownership, discoverability, or representation hiding.

## Response Accessors

- Schema fields describe the wire; capability accessors provide the pleasant application API. Keep
  these roles separate.
- Return `lent T` for immutable access to stored strings, sequences, objects, and `RawJson`. Return
  scalar values and enums by value.
- Where useful and safe, pair a direct indexed-storage accessor with a `var T` overload that returns
  the underlying storage directly. Semantic selection accessors such as `firstText` return `lent T`
  only. Never return a borrow through a temporary local.
- A `var T` overload earns its keep only for a direct-storage accessor to a real owned payload
  (a `seq` or string) that a caller may want to drain with `move(...)`: auto-sink never fires
  through an accessor call, so the overload's entire value is enabling explicit ownership transfer.
  Do not add `var` overloads for derived values, semantic selections, or scalars.
- Validate indices before indexing. Route repeated failure cases through one private
  `{.noinline, noreturn.}` helper that raises a precise `ValueError`.
- For required optional data, expose `hasX` and a strict accessor. The strict accessor raises rather
  than returning a fabricated string, object, sequence, or raw payload.
- Chat convenience accessors accept `i = 0` because `choices` contains homogeneous
  alternative completions. Validate the choice index before inspecting text or function calls.
- Responses convenience accessors must not treat `output[0]` as an assistant message. The `output`
  sequence is heterogeneous, so `firstText`, `allTextParts`, and function-call helpers scan output
  items in response order. Positional access is explicit through `outputItem(outputIndex)`.
- Function-call convenience APIs should likewise use consistent names and strict failure behavior:
  `functionCalls`, `hasFunctionCalls`, `firstCallId`, `firstCallName`, `firstCallArgs`, and
  `parseFirstCallArgs`.

## Error Handling

- Return `bool` when success or failure is the whole result, as with parse-into-destination helpers.
- Raise the closest catchable exception for invalid indices or missing values requested through a
  strict accessor. Use a custom exception only when callers can meaningfully handle it differently.
- Do not use `Defect` for malformed remote data or caller-visible absence.
- Catch only at a boundary that can translate, recover, or record the failure. Do not catch bare
  `Exception`.
- Batch JSONL output is a sum of response and error. Expose `hasOutputResponse` /
  `outputResponseOf` and `hasOutputError` / `outputErrorOf`, then build scalar accessors on those
  strict object accessors.
- Keep OpenAI error-envelope parsing compatible with unknown fields and expose the inner error with a
  borrowed accessor rather than requiring callers to understand envelope storage.

## Nim Style

- Indent with 2 spaces; never use tabs. Keep lines at or below 100 characters where practical.
- Types and enums use `PascalCase`; procs, variables, parameters, and fields use `camelCase`; modules
  use lowercase names with underscores where helpful. Wire fields remain `snake_case`.
- Use `std/...` imports and group imports from the same package.
- Default to `proc`. Use `func` only when checked purity is useful, `template` for required call-site
  substitution, and `macro` only for genuine syntax transformation.
- Use `let` by default and `var` only for mutation. Keep declarations near first use.
- Initialize objects with constructors rather than a sequence of field assignments.
- Mark one-expression accessors and forwarders `{.inline.}`.
- Keep control flow explicit. Use `case` for closed variants. Do not use `continue`.
- Use ordinary call syntax in complex expressions and tests; avoid command syntax where precedence
  can be ambiguous.

## Testing and Verification

- This project does not use `unittest`.
- Tests are standalone `tests/t*.nim` programs organized with named `block` scopes and `doAssert` /
  `doAssertRaises`.
- Keep tests deterministic, offline, and bounded. Add focused serialization tests for exact request
  JSON and parsing tests for realistic response fixtures.
- For each custom writer, test required fields, every variant, omission of defaults, and explicit
  non-default overrides.
- For each union decoder, test every arm, wrong token kinds, JSON `null` where supported, and nested
  unknown-field policy propagation.
- Test both compatible decoding (`ufSkip`) and strict decoding (`ufReject`) for every public parser.
- For accessors, test valid indexes, invalid indexes, missing values, borrowed/mutable overloads where
  present, and sentinel behavior where documented.
- Run from the repository root:

  ```sh
  nim c -r tests/tester.nim
  nim c -d:release -r tests/tester.nim
  nim c -d:danger -r tests/tester.nim
  ```

- Compile relevant examples after public API changes:

  ```sh
  nim c examples/live_ocr_retry.nim
  nim c examples/live_batch_chat_polling.nim
  ```

- Run `git diff --check` before handoff. Do not commit generated test binaries.

## Dependencies, Documentation, and Changes

- Use Atlas for dependency setup and updates. Do not add Nimble-based dependency installation steps
  to documentation or automation.
- Check the current official OpenAI API documentation before adding or changing protocol fields.
  Prefer current documented fields and explicitly exclude deprecated ones.
- Update the README and examples when a public constructor, type, default, or accessor changes.
- Public documentation should show the ergonomic capability API first, not manual schema assembly or
  transport internals.
- Commit messages are short and imperative.
- Pull requests and handoffs must state the behavior/API change, any breaking compatibility impact,
  and the test files and configurations exercised.
