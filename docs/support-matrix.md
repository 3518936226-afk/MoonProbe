# Supported contract subset

| Feature | Behavior |
| --- | --- |
| type | Exactly one explicit object, array, string, integer, number, boolean or null |
| ToolSpec input | Root must be object; output schema optional |
| properties | Declared property schemas; absent means no declared properties |
| required | Distinct strings referring to declared properties |
| additionalProperties | Boolean only; omitted means true |
| items | One explicit item schema, required for arrays |
| minItems / maxItems | Nonnegative integers, <=64; contradictory bounds rejected |
| minLength / maxLength | Unicode code points, <=1024; contradictory bounds rejected |
| minimum / maximum | Inclusive finite Double bounds within +/-9007199254740991 |
| integer | Integral finite Double in the safe-integer range |
| number | Finite IEEE-754 Double in that range; no arbitrary precision guarantee |
| enum | 1..64 scalar members of the declared type; every member must satisfy bounds |
| title / description | String schema annotations only; ignored by fingerprint |
| Everything else | Rejected at import with a path, including $ref, format, pattern, compositions, type arrays and boolean schemas |

Schema depth <=8. Worst-case generated input estimate <=512 structural nodes and <=65536 JSON bytes. String estimate conservatively budgets 6 UTF-8 JSON bytes per code point. Every JSON input/artifact is capped at 1 MiB. JSON parsing rejects duplicate keys, malformed UTF-8 and excessive nesting. A supported schema may exceed the aggregate artifact budget at a large --cases value; use fewer cases rather than silently dropping evidence.

1..200 cases per run; up to 2000 seeded-generation attempts; up to 100 shrink candidates per failed case. Candidate field order is lexical and canonical JSON ordering is deterministic. Null and false are distinct. Arrays are ordered. Equivalent textual number representations are normalized numerically.

The extract_deadline example has an explicit date enum; date format validation is outside this subset. echo is a built-in synthetic identity adapter used to check contracts without an output schema. No network and no credentials are needed after build.

## v0.2 generation and reduction budgets

The 200-case limit is an upper bound on unique cases. At most 2000 candidate visits and 2000 witness obligations are accepted; over-large catalogues fail explicitly. Produced cases remain within 512 nodes and 65536 bytes; an out-of-budget witness stays uncovered with a reason. Full report/corpus files must each fit 1 MiB. Shrink visits default to 100 and can be configured to 1000; these include duplicate and rejected candidates, unlike the legacy accepted-size-only counter. Enum complements and optional-presence pairwise limits are described in v0.2-design.md.
