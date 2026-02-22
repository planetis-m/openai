# Package
version = "0.1.0"
author = "openai"
description = "OpenAI-style chat-completions helpers for Nim + relay"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.2.0"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"

task test, "Run openai package tests":
  exec "nim c -r tests/test_openai.nim"
  exec "nim c -r tests/test_openai_retry.nim"
