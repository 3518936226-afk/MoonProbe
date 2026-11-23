# Architecture

The engine is MoonBit. model.mbt defines Spec, Case, Violation, Failure, Outcome and ShrinkResult. schema.mbt compiles a checked JSON-backed subset IR: unsupported keys and contradictory/resource-exceeding schemas are rejected before generation. The JSON representation is retained for inspect and traceability; this release does not claim a separate general-purpose JSON Schema AST library.

generator.mbt produces a legal baseline, positive boundaries, single-point mutations and xorshift32-seeded legal samples. Properties are processed in lexical UTF-16 key order. Repeated legal inputs are permitted when filling a requested case budget; index distinguishes cases. It is not a coverage guarantee. Scalar enum enumeration makes the demo leap-day case reproducible without a date-specific generator.

runner.mbt validates the input expectation before dispatch. Expected invalid inputs pass without calling adapters. Valid inputs call one deterministic in-process adapter; output is checked only if an output schema exists. Failure identity is the tool name plus stage, rule code and JSON Pointer. Required-field pointers identify the missing child.

Shrinking visits field deletion, nested array/string and numeric reductions in stable order. An accepted input must retain the original validation expectation and execution failure signature, and strictly reduce the tuple (structural node count, canonical UTF-8 JSON bytes). The algorithm restarts after each accepted candidate; it stops at a local minimum or the attempt limit. Raw source records are never mutated.

The SHA-256 contract fingerprint covers tool name and normalized input/output schemas, excluding only schema title/description annotations. Properties named title or description remain semantic. Canonical serialization uses lexical_compare explicitly: MoonBit's default String comparison is length-first. JSON Pointer escapes ~ and / according to RFC 6901. No full RFC 8785 interoperability is claimed.

report.mbt saves both original and reduced inputs and the original expectation. Replay validates compatibility for the complete batch before running it. Source-version changes within the registered family are allowed; contract changes require new corpus generation. A different signature is a failure, not a repair.

cmd/moonprobe contains strict CLI parsing, IO and benchmark scheduling. native_io.c is a small UTF-8-aware Windows/POSIX filesystem shim: bounded file reads, exclusive writes, existence checks and directory creation. There is no adapter, validator, generator, shrinker or report business logic in C. File paths cannot contain NUL. Failures are surfaced as configuration or environment errors. If artifact writing fails mid-command, partial files can remain; use a fresh output directory for a retry.

The MinGW build calls the pinned official compiler's package/link plan, then GCC links generated C plus official runtime.c, env.c, utf.c and backtrace.c unchanged. The entire async runtime is not needed by this program. The same route builds the official MoonBit native test driver; the Harness checks every result message and count because the driver's process exit code alone is not an assertion summary.

Native CI is configured to use the same Harness. Other backends and OS combinations are unvalidated. No real execution, external process adapter, MCP transport or HTTP runtime is exposed.
