# Architecture (v0.2.1)

The domain logic is MoonBit: schema.mbt checks the supported subset and resource capacity, ir.mbt compiles typed Schema/Shape nodes, generator.mbt creates unique bounded coverage witnesses and per-path seeded samples, adapters.mbt validates input expectations and returned outputs, shrink.mbt performs lazy schema-aware same-signature reduction, and report.mbt stores distinct failures, explicit costs and v1/v2 replay data.

Expected-invalid cases are checked locally without calling tools. Valid cases use an Adapter family/version/invoke interface. Reports distinguish main calls, shrink calls, actual validations and cache hits; shared signatures are not inferred root causes. Coverage witnesses and finite-space termination have the exact limited meanings in v0.2-design.md.

Shrinking compares structural nodes, canonical UTF-8 bytes and scalar complexity, using budgets, per-call cache and accepted-step traces. It does not promise a global minimum. Deterministic generation does not make a stateful external tool deterministic.

Fingerprints cover normalized name and input/output schemas; family compatibility is separately checked during replay. Schema title/description annotations are ignored, but properties named title or description remain semantic. Canonical keys use lexical comparison; full RFC 8785 interoperability is not claimed.

cmd/moonprobe implements arguments, IO and scheduling. native_io.c provides bounded reads and exclusive writes. native_process.c provides Windows CreateProcessW, direct argv quoting, redirected stdio, timeout/output monitoring and Job Object cleanup. Neither C bridge implements schema, generation, shrinking or verdict logic. Tools execute only through explicit --process configuration, never commands embedded in ToolSpec. This is trusted process management, not a sandbox. See real-tool-case.md for limits.

The MinGW build uses the pinned official compiler plan and links four unmodified synchronous runtime sources. The official builder for this compiler version also plans MSVC-only async runtime objects, so scripts/build-native.ps1 is the supported MinGW entrypoint. Harness inspects every generated Native result because exit status alone can miss assertions.

Windows x64 Native is the supported target. MCP transport, HTTP runtime, LLM semantic judgments and human sign-off are not implemented. cmd/oracle is a development-only independent validator driver. legacy modules are named v0.1 comparison baselines.
The v0.2.2 argument bridge in cmd/native_args.h reads Windows UTF-16 arguments through CommandLineToArgvW and returns a FixedArray across the C ABI. It avoids the pinned runtime's ANSI MinGW fallback without modifying upstream sources. Harness checks exact Unicode paths, including a Chinese/emoji input filename.
