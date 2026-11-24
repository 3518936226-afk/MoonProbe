# Participant review: understanding and sign-off

Status: pending personal review. This checklist is preparation, not a claim that the participant has completed it.

- Explain why expected-invalid inputs never invoke a tool, and why independently declared mutation expectations avoid circular testing.
- Trace ToolSpec to typed IR, generation, adapter execution, shrinking and replay. Name the schema subset and limits.
- Explain canonical deduplication, the coverage witness catalogue, independent path seeds and bounded termination. Distinguish witness coverage from branch or semantic correctness.
- Explain the node/byte/scalar shrink ranking, same-signature requirement, cache and budget. Show why global minimality is not guaranteed.
- Demonstrate the real URL-form case: parse_qs defaults drop empty fields, while the consumer requires one value. Explain the keep_blank_values fix without calling it an upstream bug.
- Show one original and reduced input and replay it against both configurations. Explain main/shrink call counts and the difference between failure signatures and root causes.
- Explain why 10,000 differential pairs, selected official fixtures and 12 compiled mutants strengthen confidence but do not establish complete standards compliance.
- Explain which logic is MoonBit and which C code handles OS details. Describe the trusted-process boundary and why it is not a sandbox.
- Identify AI-authored changes, the verification actually performed, and unresolved human/real-user evidence.
- Verify the competition's current dates and participation requirements. Join its group and use 3518936226-afk as your nickname.

Record your own date, reviewed commit and understanding after completing these tasks. No automatic signature is supplied.