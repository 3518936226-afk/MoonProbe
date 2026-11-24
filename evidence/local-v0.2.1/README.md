# Frozen local verification: v0.2.1

All summaries refer to source commit da358f2841db20c46db8cb18615be174bf62f0cc. They are original local results from before public-source synchronization, not results for a later documentation/CI commit. Paths inside summaries identify the original Windows machine; rerun scripts to create current paths.

| Evidence | Actual result |
| --- | --- |
| harness-summary.json | 66 checks, 29 Native unit groups passed |
| clean-summary.json | Same 66 checks passed from a fresh clone |
| process-summary.json | 64 checks passed; actual stdlib default configuration 3 failures, corrected configuration 0 |
| independent-summary.json | 100 schemas, 10,000 pairs, 0 mismatches; 3,733 generated unique inputs independently checked; 57 original upstream cases selected, 2,870 excluded with reasons |
| mutation-summary.json | 12 defined source mutants compiled; 12 killed, 0 survived |
| benchmark-summary.json | Raw same-machine timing samples; no cross-machine or blanket-speedup claim |
| semantic-roundtrip.json | Seven actual stdlib roundtrip inputs, separate from schema shape checks |
| default-replay.log / fixed-replay.log | Same saved inputs reproduce first and pass after configuration change |

The public delivery ZIP contains the complete original logs, vectors, exclusion ledger, corpus and per-file manifest. SHA-256: 1ca5368641c9f744155585335b8980098101fd1789362735d16f43d05cefd7f5. New remote runs are linked through GitHub Actions and upload their own evidence artifact. This snapshot never substitutes for a successful remote run or independent human trial.