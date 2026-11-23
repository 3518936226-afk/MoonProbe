# Demonstration

1. Inspect examples/extract-deadline.json. Show the date enum, required input date and required output deadline. Explain that format semantics are out of scope.
2. Run the README buggy command with seed 20261123 and 32 cases into a fresh directory. Exit 1 is expected.
3. Open report.json. Show OUTPUT_SCHEMA / REQUIRED /deadline on legal 2024-02-29, and confirm expected-invalid inputs never called the adapter.
4. Show the original and reduced inputs. The reduced object contains only date. Compare node/byte counts and note the shrink attempt limit.
5. Replay the same corpus with buggy: reproduced and exit 1. Switch only --mock to fixed: fixed and exit 0.
6. Show Harness summary, benchmark raw samples, scope log and pending external evidence. Do not describe injected failures as real defects or local execution as independent human verification.

A recorded terminal demonstration can be generated from the shipped executable. Its command transcript and recording must match the binary SHA-256 in the delivery manifest. A generated transcript video is not a live screen recording; label it accurately.

The delivered GIF is explicitly labelled as rendered actual command output, not desktop capture. The desktop automation inventory did not expose a targetable demonstration window. A live WinForms helper is supplied for a later user-operated screen recording; that recording remains pending. The renderer uses Pillow and an existing Windows Consolas font and is not required by the CLI or Harness.

For v0.2, show requested/generated unique counts, covered/eligible/uncovered targets, failure_signature_count and execution.total_adapter_calls. Run bench --workload compare to show old/new middle-substring, same-byte numeric and array interval reductions. Report quality and cost together, including scenarios where the new method uses more calls. Historical v1 corpus compatibility is part of the Native Harness.
