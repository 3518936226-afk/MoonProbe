# Local v0.2.2 verification

Source revision: 01fbb786b0c7ca41ffd00309ab1996cee83dc254. The original summaries in this directory bind that revision, not future documentation or merge commits.

- harness-summary.json: 68 checks including 29 Native unit groups passed. Unicode output must exist at its exact requested location, and a Chinese/emoji ToolSpec filename is exercised.
- process-summary.json: 64 integration and transport checks passed.
- independent-summary.json: 100 schemas, 10,000 pairs, 0 mismatches; production-generated inputs and selected original fixtures independently checked.
- mutation-summary.json: all 12 successfully compiled source mutants killed.
- benchmark-summary.json: actual local samples, no cross-machine speed claim.
- unicode-before-after.json: the unchanged v0.2.1 executable exits 0 but misses the requested Chinese report path on this machine; v0.2.2 exits 0 and writes the exact path.

The first remote failure and tracked fix are at https://github.com/3518936226-afk/MoonProbe/issues/3 . These local results are separate from the Actions run and never count as independent human review.