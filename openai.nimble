# Package
version = "1.3.0"
author = "planetis-m"
description = "OpenAI-style chat-completions helpers for Nim + relay"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.2.0"
requires "https://github.com/planetis-m/jsonx >= 0.6.0"
requires "https://github.com/planetis-m/relay"

task test, "Run openai package tests":
  exec "nim c -r tests/tester.nim"
