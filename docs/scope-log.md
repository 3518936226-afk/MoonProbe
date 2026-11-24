# Scope log

2026-11-23: Full P0 selected by user. No Web UI, real MCP/HTTP calls, LLM semantic scoring or cloud deployment.

2026-11-23: D:\VAPP is absent and the D-drive root grants no normal user write permission. Continue the existing D:\Users\LX\VAPP\moonprobe directory. All configurable temporary/build/cache paths stay here.

2026-11-23: Official MoonBit v0.10.22 Native builder unconditionally builds the Windows async runtime, which requires MSVC. No usable MSVC was found. MinGW GCC 15.2 is available. build-native.ps1 uses the official compiler planner, compiles the emitted MoonBit C and links four unmodified official synchronous runtime source files. A small C file handles UTF-8 Windows paths and exclusive local file IO. No engine logic moved out of MoonBit. Direct moon build/test remains a known incompatibility on this MinGW environment; the tested build and Harness commands are the acceptance entrypoints.

2026-11-23: Expanded inputs are additionally capped at 512 nodes and an estimated 65536 UTF-8 JSON bytes, scalar enums at 64 members. Reports and corpus files must fit 1 MiB or the command fails with a budget diagnostic. This avoids exponential allocation before generation.

2026-11-23: Git history is local, with AI-authored commits explicitly attributed to Codex. Public repository creation, uploads, remote CI, competition registration and human review have not been performed. Source and CI configuration are prepared locally.

2026-11-23: Synthetic extract_deadline and echo fixtures only. No claim of a real-world defect, independent human reproduction or speedup over manual testing. Those evidence categories remain pending.

## v0.2 core depth

The user selected algorithm quality and reliability. Scope: typed IR, independent local adapter interface, unique deterministic coverage witnesses, optional sibling pairwise presence, bounded ddmin-style shrinking, explicit costs and v1/v2 corpus replay. No new real-tool transport, LLM semantics or UI product is added. --cases now means an upper bound; reports explain short runs.

The independent oracle is development-only, pinned to jsonschema 4.26.0 with Windows Python 3.12 wheel hashes. Upstream fixtures are vendored verbatim at a fixed commit with their MIT license. A filtered subset and an exclusion ledger are produced; unsupported data is not silently relabelled. Source mutations run only in D-drive scratch copies.

The first comparative run found 197 unique inputs in 200 legacy cases versus 200 unique v0.2 inputs. The middle-substring case reduced from the legacy 42-byte retained input to a 14-byte input; the array case reached 15 bytes versus 27 within equal 100-visit settings, with calls 14 versus 75. Legacy visit counters count fewer categories, so these counters are not presented as equal-work guarantees. Timings and actual callback counts remain separately recorded.

## Public-source publication

2026-11-24: User authorized completion of the public repository. Preserve original development commits and existing GitHub upload commits by merging their histories. Expose source, licenses, examples, frozen local evidence, participation-review guidance and actual CI. Fix moving toolchain URLs and configure the cloud MinGW path explicitly. Registration, group membership, participant sign-off and independent human trials are not performed by this change.
