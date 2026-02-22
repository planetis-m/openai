import std/random
import openai_retry

proc main() =
  let policy = defaultRetryPolicy(
    maxAttempts = 5,
    baseDelayMs = RetryBaseDelayMs,
    maxDelayMs = RetryMaxDelayMs,
    jitterDivisor = RetryJitterDivisor
  )

  var rng = initRand(42)
  var delays: seq[int] = @[]
  for attempt in 1..policy.maxAttempts:
    delays.add(retryDelayMs(rng, attempt, policy))

  doAssert delays.len == policy.maxAttempts
  doAssert delays[0] >= backoffBaseMs(1, policy.baseDelayMs, policy.maxDelayMs)

  echo "retry example: attempts=", policy.maxAttempts,
    " firstDelayMs=", delays[0],
    " lastDelayMs=", delays[^1]

when isMainModule:
  main()
