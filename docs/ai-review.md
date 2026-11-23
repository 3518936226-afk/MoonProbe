# AI-assisted review record

Tool: Codex. Date: 2026-11-23, Asia/Shanghai. Scope: Schema, generation, Runner, IO, fingerprinting, shrinking and replay. This is AI self-review with executable checks, not an independent reviewer or a human sign-off.

| Finding | Reproduction / location | Handling and evidence |
| --- | --- | --- |
| Windows Native runtime builds MSVC-only objects under MinGW | Direct official moon build attempts event_bus.c, fs.c and thread_pool.c and fails | Use documented compiler-plan + synchronous-runtime linking. Full Harness verifies produced binaries. Scope deviation recorded. |
| Option-to-JSON implicit encoding produced arrays instead of nullable objects | Optional output/failure fields in initial CLI output | Explicit null/object conversion. CLI fixed report and replay assertions cover the wire format. |
| Default String comparison is length-first | Unequal-length JSON keys serialized in unexpected order | Explicit lexical_compare; S06 regression checks alphabet before z. |
| Annotation filtering could remove a property literally named description | Two ToolSpecs with different description-property types | Traverse schema nodes separately from property maps; S05 verifies fingerprints. |
| Nested array bounds can multiply allocations | Two maxItems=64 array levels | Expanded-node/byte budget checked before generation; S07 regression. |
| Native test runner exits zero even when a result may carry failure text | Official generated test-driver protocol | Harness counts result entries and requires empty messages for every test. |
| Existing output could be overwritten or a path mishandled | Reused --out and Unicode path | Exclusive C writes, no-overwrite checks, UTF-16 Windows path conversion. CLI Harness cases cover them. |

All accepted changes are rerun through the complete Harness before release. Source commits and final verification paths are listed in evidence/index.json. Human decisions, independent review and actual tool-user trials remain pending. No review model identifier beyond the known tool name is invented.

Clean-directory reproduction found a compiler-plan portability issue: an external MOON_HOME is emitted as a symbolic shell variable and the compiler command is named moonc rather than a relative moonc.exe. The build script now expands only that known placeholder and binds the pinned compiler explicitly. Reproduced with a clean local clone and a shared pinned toolchain; complete Harness passed.

The numeric shrink fixture was corrected from 4 to 40: changing one digit to another does not reduce canonical byte size and must not be accepted under the declared measure. H04 now uses a genuinely reducible numeric input and also verifies array reduction. H03 creates an alternate failure on a smaller candidate and verifies that the shrinker refuses it.
