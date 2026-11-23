///|
pub fn test_report(
  spec : Spec,
  seed : Int32,
  count : Int32,
  version : String,
) -> Json raise ProbeError {
  let cases = generate(spec, seed, count)
  let results : Array[Json] = []
  let corpus : Array[Json] = []
  let mut calls = 0
  let mut failed = 0
  for c in cases {
    let outcome = run_case(spec, c, version)
    if outcome.called {
      calls += 1
    }
    let f = outcome.failure
    let mut details : Json = Json::null()
    if f is Some(signature) {
      failed += 1
      let reduced = shrink(spec, c, version)
      details = {
        "attempts": reduced.attempts,
        "termination": reduced.reason,
        "original_nodes": nodes(c.args),
        "reduced_nodes": nodes(reduced.args),
        "original_bytes": byte_size(c.args),
        "reduced_bytes": byte_size(reduced.args),
        "reduction_ratio": 1.0 -
        byte_size(reduced.args).to_double() / byte_size(c.args).to_double(),
      }
      corpus.push({
        "format_version": 1,
        "tool_name": spec.name,
        "schema_fingerprint": spec.fingerprint,
        "adapter_family": spec.adapter,
        "source_version": version,
        "seed": seed,
        "index": c.index,
        "category": c.category,
        "expected": expected_json(c.expected),
        "signature": failure_json(signature),
        "original_input": c.args,
        "reduced_input": reduced.args,
        "shrink": details,
      })
    }
    results.push({
      "case": case_json(c, seed),
      "called": outcome.called,
      "failure": f.map(failure_json).unwrap_or(Json::null()),
      "shrink": details,
    })
  }
  {
    "format_version": 1,
    "engine_version": "0.1.0",
    "tool_name": spec.name,
    "schema_fingerprint": spec.fingerprint,
    "adapter_family": spec.adapter,
    "adapter_version": version,
    "seed": seed,
    "budgets": {
      "cases": count,
      "generation_attempts": 2000,
      "shrink_attempts_per_failure": 100,
    },
    "passed": count - failed,
    "failed": failed,
    "adapter_calls": calls,
    "results": results,
    "corpus": corpus,
  }
}

///|
fn decode_expected(j : Json) -> Violation? raise ProbeError {
  if j == Json::null() {
    return None
  }
  if !type_is("string", field(j, "code")) ||
    !type_is("string", field(j, "path")) ||
    text(field(j, "code")) == "" {
    raise Invalid("invalid corpus expected rule")
  }
  Some({ code: text(field(j, "code")), path: text(field(j, "path")), })
}

///|
pub fn replay_report(
  spec : Spec,
  entries : Array[Json],
  version : String,
) -> Json raise ProbeError {
  if entries.is_empty() || entries.length() > 200 {
    raise Invalid("corpus must contain 1..200 entries")
  }
  let results : Array[Json] = []
  let mut failed = 0
  // Validate every entry first; incompatible corpora never produce partial verdicts.
  for e in entries {
    if field(e, "format_version") != Json::number(1.0) ||
      text(field(e, "schema_fingerprint")) != spec.fingerprint ||
      text(field(e, "adapter_family")) != spec.adapter ||
      text(field(e, "tool_name")) != spec.name {
      raise Invalid("CORPUS_INCOMPATIBLE: version, fingerprint, family or tool")
    }
    if !has(e, "original_input") ||
      !has(e, "reduced_input") ||
      !has(e, "expected") {
      raise Invalid("CORPUS_INVALID: missing inputs or expectation")
    }
    let expected = decode_expected(field(e, "expected"))
    if validate(spec.input, field(e, "original_input")) != expected ||
      validate(spec.input, field(e, "reduced_input")) != expected {
      raise Invalid("CORPUS_INVALID: input violates stored expectation")
    }
    let sig = field(e, "signature")
    for k in ["stage", "code", "path"] {
      if !type_is("string", field(sig, k)) {
        raise Invalid("CORPUS_INVALID: missing signature field")
      }
    }
    if text(field(sig, "stage")) == "" || text(field(sig, "code")) == "" {
      raise Invalid("CORPUS_INVALID: empty signature")
    }
  }
  for e in entries {
    let c : Case = {
      index: 0,
      args: field(e, "reduced_input"),
      category: "replay",
      expected: decode_expected(field(e, "expected")),
    }
    let actual = run_case(spec, c, version).failure
    let status = match actual {
      None => "fixed"
      Some(f) => {
        failed += 1
        if failure_json(f) == field(e, "signature") {
          "reproduced"
        } else {
          "different_failure"
        }
      }
    }
    results.push({
      "status": status,
      "original_signature": field(e, "signature"),
      "actual_signature": actual.map(failure_json).unwrap_or(Json::null()),
      "input": c.args,
    })
  }
  {
    "format_version": 1,
    "engine_version": "0.1.0",
    "schema_fingerprint": spec.fingerprint,
    "adapter_family": spec.adapter,
    "adapter_version": version,
    "passed": entries.length() - failed,
    "failed": failed,
    "results": results,
  }
}
