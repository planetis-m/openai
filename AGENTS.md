# Repository Guidelines

## Project Structure & Modules
- `src/`: Core OpenAI-facing library modules.
  - `openai.nim`: chat-completions API helpers and response accessors.
  - `openai_schema.nim`: direct JSON-mapped schema types.
  - `openai_retry.nim`: optional retry/backoff helpers.
- `tests/`: Executable test programs and local `tests/config.nims`.
- `examples/`: Runnable examples and local `examples/config.nims`.
- Root files:
  - `openai.nimble`: package metadata and test task.
  - `config.nims`: project-local source path setup.
  - `nim.cfg`: Atlas-managed dependency paths. Do not hand-edit.

## Build, Test, and Development
- Dependency workflow: use Atlas workspace/deps setup.
- Do not add Nimble-based dependency install steps to docs/automation for this repo.
- Use `nim` compile/run commands directly.
- Run tests:
  - `nim c -r tests/test_openai.nim`
  - `nim c -r tests/test_openai_retry.nim`
- Build examples:
  - `nim c test_live_ocr.nim`
  - `nim c examples/live_batch_chat_polling.nim`

## Coding Style & Naming
- Indentation: 2 spaces, no tabs.
- Nim naming:
  - Types/enums: `PascalCase`
  - Procs/vars/fields: `camelCase`
  - Modules/files: lowercase with underscores where helpful.
- Keep control flow explicit; avoid hidden transport abstractions over Relay.

## Testing Guidelines
- This project does **not** use `unittest`.
- Tests are standalone Nim programs using `doAssert`.
- Add tests under `tests/` with `test_<topic>.nim` naming.
- Keep tests deterministic and bounded.

## Commit & Pull Requests
- Commit messages: short, imperative.
- PRs should include:
  - behavior/API change summary
  - compatibility notes for public API renames
  - test coverage notes (which test files changed)
- Ensure test commands above compile and run successfully before merge.
