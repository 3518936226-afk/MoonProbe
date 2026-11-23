# Scope log

2026-11-23: Full P0 selected by user. No Web UI, real MCP/HTTP calls, LLM semantic scoring or cloud deployment.

2026-11-23: D:\VAPP is absent and the D-drive root grants no normal user write permission. Continue the existing D:\Users\LX\VAPP\moonprobe directory. All configurable temporary/build/cache paths stay here.

2026-11-23: Official MoonBit v0.10.22 Native builder unconditionally builds the Windows async runtime, which requires MSVC. No usable MSVC was found. MinGW GCC 15.2 is available. build-native.ps1 uses the official compiler planner, compiles the emitted MoonBit C and links four unmodified official synchronous runtime source files. A small C file handles UTF-8 Windows paths and exclusive local file IO. No engine logic moved out of MoonBit. Direct moon build/test remains a known incompatibility on this MinGW environment; the tested build and Harness commands are the acceptance entrypoints.

2026-11-23: Expanded inputs are additionally capped at 512 nodes and an estimated 65536 UTF-8 JSON bytes, scalar enums at 64 members. Reports and corpus files must fit 1 MiB or the command fails with a budget diagnostic. This avoids exponential allocation before generation.

2026-11-23: Git history is local, with AI-authored commits explicitly attributed to Codex. Public repository creation, uploads, remote CI, competition registration and human review have not been performed. Source and CI configuration are prepared locally.

2026-11-23: Synthetic extract_deadline and echo fixtures only. No claim of a real-world defect, independent human reproduction or speedup over manual testing. Those evidence categories remain pending.
