# Local build config for tests
switch("path", "../src")

switch("threads", "on")
switch("mm", "atomicArc")

# libcurl
switch("passC", "-DCURL_DISABLE_TYPECHECK")
switch("passL", "-lcurl")
