# Local build config for examples
switch("path", "../src")

switch("threads", "on")
switch("mm", "atomicArc")

# libcurl
switch("passC", "-DCURL_DISABLE_TYPECHECK")
switch("passL", "-lcurl")
