///|
pub fn test_report(
  spec : Spec,
  seed : Int32,
  count : Int32,
  version : String,
  budget~ : Int32 = 100,
) -> Json raise ProbeError {
  test_adapter_report(
    spec,
    seed,
    count,
    local_adapter(spec.adapter, version),
    budget~,
  )
}

///|
pub fn test_adapter_report(
  spec : Spec,
  seed : Int32,
  count : Int32,
  adapter : Adapter,
  budget~ : Int32 = 100,
) -> Json raise ProbeError {
  let version = adapter.version
  if budget < 1 || budget > 1000 {
    raise Invalid("shrink budget must be 1..1000")
  }
  let generated = generate_result(spec, seed, count)
  let cases = generated.cases
  let results : Array[Json] = []
  let corpus : Array[Json] = []
  let groups : Map[String, Array[Int32]] = Map([])
  let mut main_calls = 0
  let mut shrink_calls = 0
  let mut validations = 0
  let mut hits = 0
  let mut failed = 0
  let reduced_cache : Map[String, DeepShrink] = Map([])
  for c in cases {
    let outcome = run_adapter(spec, c, adapter)
    if outcome.called {
      main_calls += 1
    }
    validations += validation_count(spec, outcome)
    let mut details : Json = Json::null()
    if outcome.failure is Some(signature) {
      failed += 1
      let group = canonical(failure_json(signature))
      if !groups.contains(group) {
        groups[group] = []
      }
      groups[group].push(c.index)
      let key = sha256(canonical(c.args) + canonical(expected_json(c.expected)))
      let reduced = match reduced_cache.get(key) {
        Some(r) => r
        None => {
          let r = shrink_adapter(spec, c, adapter, budget~)
          reduced_cache[key] = r
          shrink_calls += r.adapter_calls
          validations += r.validations
          hits += r.cache_hits
          r
        }
      }
      details = {
        "attempts": reduced.attempts,
        "termination": reduced.reason,
        "original_nodes": nodes(c.args),
        "reduced_nodes": nodes(reduced.args),
        "original_bytes": byte_size(c.args),
        "reduced_bytes": byte_size(reduced.args),
        "reduction_ratio": 1.0 -
        byte_size(reduced.args).to_double() / byte_size(c.args).to_double(),
        "adapter_calls": reduced.adapter_calls,
        "validations": reduced.validations,
        "cache_hits": reduced.cache_hits,
        "rejected_input": reduced.rejected_input,
        "rejected_signature": reduced.rejected_signature,
        "rejected_size": reduced.rejected_size,
        "accepted_steps": reduced.trace,
      }
      corpus.push({
        "format_version": 2,
        "generator_version": "coverage-v2",
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
      "failure": outcome.failure.map(failure_json).unwrap_or(Json::null()),
      "shrink": details,
    })
  }
  let signatures = groups.keys().collect()
  signatures.sort_by((a, b) => a.lexical_compare(b))
  {
    "format_version": 2,
    "engine_version": "0.2.2",
    "generator_version": "coverage-v2",
    "tool_name": spec.name,
    "schema_fingerprint": spec.fingerprint,
    "adapter_family": spec.adapter,
    "adapter_version": version,
    "seed": seed,
    "requested_cases": count,
    "generated_cases": cases.length(),
    "generation": {
      "visited": generated.visited,
      "duplicates_removed": generated.duplicates,
      "termination": generated.termination,
    },
    "coverage": generated.coverage,
    "budgets": {
      "cases": count,
      "generation_attempts": 2000,
      "shrink_attempts_per_failure": budget,
    },
    "passed": cases.length() - failed,
    "failed": failed,
    "adapter_calls": main_calls,
    "execution": {
      "main_adapter_calls": main_calls,
      "shrink_adapter_calls": shrink_calls,
      "total_adapter_calls": main_calls + shrink_calls,
      "validation_calls": validations,
      "shrink_cache_hits": hits,
    },
    "failure_signature_count": signatures.length(),
    "failure_groups": signatures.map(k => {
      let row : Json = {
        "signature": @json.parse(k) catch {
          _ => Json::null()
        },
        "case_indices": groups[k],
        "count": groups[k].length(),
      }
      row
    }),
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
  replay_adapter_report(spec, entries, local_adapter(spec.adapter, version))
}

///|
pub fn replay_adapter_report(
  spec : Spec,
  entries : Array[Json],
  adapter : Adapter,
) -> Json raise ProbeError {
  let version = adapter.version
  if entries.is_empty() || entries.length() > 200 {
    raise Invalid("corpus must contain 1..200 entries")
  }
  let results : Array[Json] = []
  let mut failed = 0
  // Validate every entry first; incompatible corpora never produce partial verdicts.
  for e in entries {
    if (
        field(e, "format_version") != Json::number(1.0) &&
        field(e, "format_version") != Json::number(2.0)
      ) ||
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
    let actual = run_adapter(spec, c, adapter).failure
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
    "engine_version": "0.2.2",
    "schema_fingerprint": spec.fingerprint,
    "adapter_family": spec.adapter,
    "adapter_version": version,
    "passed": entries.length() - failed,
    "failed": failed,
    "results": results,
  }
}
