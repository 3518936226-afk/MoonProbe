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

## v0.2 review and independent checks

The second implementation removes validator-derived negative expectations. Mutation strategies declare rule/path independently, and generated witnesses are checked against them. An independent Python validator and unmodified upstream expectations check validity; handcrafted Native tests check precise rule and pointer semantics.

Additional findings addressed: repeated filler cases; identical random draws shared across fields/items; coverage goal collisions between array positions; duplicated min=max obligations; eager reduction candidate construction; equal-byte numeric reductions; validation counts inferred from error text; and incomplete test metadata selection after adding a second test file. Native regression tests exercise each change.

Twelve predetermined, successfully compiled source mutations test omission of required/additional-property rules, fractional integers, inclusive endpoints, Unicode code points, enum, array items, nested properties, output checks, failure signatures and fingerprint comparison. Compile failure, timeout and missing result messages are not accepted as killed mutants. The final summary supplies actual outcomes and source hashes.

Coverage is conservative witness coverage of the declared target catalogue. A fully covered catalogue does not prove that every fault or branch was explored. Root causes are not inferred from signature counts. Independent machine checks are not human review; participant sign-off remains pending.
