///|
pub(all) struct DeepShrink {
  args : Json
  attempts : Int32
  reason : String
  adapter_calls : Int32
  validations : Int32
  cache_hits : Int32
  rejected_input : Int32
  rejected_signature : Int32
  rejected_size : Int32
  trace : Array[Json]
}

///|
priv struct CacheEntry {
  input_error : Violation?
  outcome : Outcome?
}

///|
fn ranks(v : Json, p : String, out : Array[(String, Double)]) -> Unit {
  match v {
    Object(m) =>
      for k in keys(v) {
        ranks(m[k], ptr(p, k), out)
      }
    Array(a) =>
      for i, x in a {
        ranks(x, ptr(p, i.to_string()), out)
      }
    Number(n, ..) => out.push((p, n.abs()))
    True => out.push((p, 1.0))
    False | Null => out.push((p, 0.0))
    String(s) => out.push((p, s.char_length().to_double()))
  }
}

///|
pub fn deep_smaller(a : Json, b : Json) -> Bool {
  if nodes(a) != nodes(b) {
    return nodes(a) < nodes(b)
  }
  if byte_size(a) != byte_size(b) {
    return byte_size(a) < byte_size(b)
  }
  let x : Array[(String, Double)] = []
  let y : Array[(String, Double)] = []
  ranks(a, "", x)
  ranks(b, "", y)
  x.sort_by((a, b) => a.0.lexical_compare(b.0))
  y.sort_by((a, b) => a.0.lexical_compare(b.0))
  for i = 0; i < x.length().min(y.length()); i = i + 1 {
    if x[i].1 != y[i].1 {
      return x[i].1 < y[i].1
    }
  }
  false
}

///|
pub fn validation_count(spec : Spec, o : Outcome) -> Int32 {
  if o.failure is Some(f) && f.code == "FAMILY_MISMATCH" {
    return 0
  }
  1 +
  (if o.called &&
    spec.output_ir is Some(_) &&
    !(o.failure is Some(f) && f.stage == "ADAPTER") {
    1
  } else {
    0
  })
}

///|
fn child_schema(s : Schema?, key : String) -> Schema? {
  match s {
    Some({ shape: Obj(props, _, _), .. }) =>
      props.filter(x => x.0 == key).get(0).map(x => x.1)
    Some({ shape: Arr(sub, _, _), .. }) => Some(sub)
    _ => None
  }
}

///|
fn lazy_candidates(
  v : Json,
  s : Schema?,
  emit : (Json, String) -> Bool,
) -> Bool {
  match v {
    Object(m) => {
      let required = match s {
        Some({ shape: Obj(_, r, _), .. }) => r
        _ => []
      }
      let removable = keys(v).filter(k => !required.contains(k))
      let mut granularity = 2
      while !removable.is_empty() && granularity <= removable.length().max(2) {
        let chunk = (removable.length() + granularity - 1) / granularity
        for start = 0; start < removable.length(); start = start + chunk {
          let copy = m.copy()
          for i = start; i < (start + chunk).min(removable.length()); i = i + 1 {
            copy.remove(removable[i])
          }
          if emit(Json::object(copy), "object_chunk") {
            return true
          }
        }
        if granularity >= removable.length() {
          break
        }
        granularity = (granularity * 2).min(removable.length())
      }
      for k in keys(v) {
        if lazy_candidates(m[k], child_schema(s, k), (x, op) => {
            emit(replace_key(v, k, x), op)
          }) {
          return true
        }
      }
    }
    Array(a) => {
      let min = match s {
        Some({ shape: Arr(_, n, _), .. }) => n
        _ => 0
      }
      let mut granularity = 2
      while a.length() > min && granularity <= a.length().max(2) {
        let chunk = (a.length() + granularity - 1) / granularity
        for start = 0; start < a.length(); start = start + chunk {
          let stop = (start + chunk).min(a.length())
          if a.length() - (stop - start) < min {
            continue
          }
          let copy : Array[Json] = []
          for i, x in a {
            if i < start || i >= stop {
              copy.push(x)
            }
          }
          if emit(Json::array(copy), "array_chunk") {
            return true
          }
        }
        if granularity >= a.length() {
          break
        }
        granularity = (granularity * 2).min(a.length())
      }
      for i, x in a {
        if lazy_candidates(x, child_schema(s, i.to_string()), (r, op) => {
            let copy = a.copy()
            copy[i] = r
            emit(Json::array(copy), op)
          }) {
          return true
        }
      }
    }
    String(text) => {
      let chars = text.iter().collect()
      let min = match s {
        Some({ shape: Str(n, _), .. }) => n
        _ => 0
      }
      let mut granularity = 2
      while chars.length() > min && granularity <= chars.length().max(2) {
        let chunk = (chars.length() + granularity - 1) / granularity
        for start = 0; start < chars.length(); start = start + chunk {
          let stop = (start + chunk).min(chars.length())
          if chars.length() - (stop - start) < min {
            continue
          }
          let copy : Array[Char] = []
          for i, x in chars {
            if i < start || i >= stop {
              copy.push(x)
            }
          }
          if emit(Json::string(String::from_array(copy)), "string_chunk") {
            return true
          }
        }
        if granularity >= chars.length() {
          break
        }
        granularity = (granularity * 2).min(chars.length())
      }
    }
    Number(n, ..) => {
      let bounds = match s {
        Some({ shape: Integral(lo, hi), .. })
        | Some({ shape: Real(lo, hi), .. }) => (lo, hi)
        _ => (None, None)
      }
      let targets = [
        0.0,
        n / 2.0,
        (n / 2.0).floor(),
        (n / 2.0).ceil(),
        bounds.0.unwrap_or(0.0),
        bounds.1.unwrap_or(0.0),
      ]
      for x in targets {
        if emit(Json::number(x), "number_simplify") {
          return true
        }
      }
    }
    True => if emit(Json::boolean(false), "boolean_simplify") { return true }
    _ => ()
  }
  false
}

///|
pub fn shrink_adapter(
  spec : Spec,
  c : Case,
  adapter : Adapter,
  budget~ : Int32 = 100,
) -> DeepShrink {
  let budget = budget.max(0).min(1000)
  let initial = run_adapter(spec, c, adapter)
  let mut calls = if initial.called { 1 } else { 0 }
  let mut validations = validation_count(spec, initial)
  let mut attempts = 0
  let mut hits = 0
  let mut input_rejected = 0
  let mut signature_rejected = 0
  let mut size_rejected = 0
  let mut best = c.args
  let trace : Array[Json] = []
  let mut reason = "not_failure"
  if initial.failure is Some(signature) {
    if nodes(c.args) > 512 || byte_size(c.args) > 65536 {
      reason = "input_budget"
    } else {
      let cache : Map[String, CacheEntry] = Map([])
      reason = "local_minimum"
      while attempts < budget {
        let mut accepted = false
        ignore(
          lazy_candidates(
            best,
            if c.expected is None {
              Some(spec.input_ir)
            } else {
              None
            },
            (candidate, operator) => {
              if attempts >= budget {
                return true
              }
              attempts += 1
              if !deep_smaller(candidate, best) {
                size_rejected += 1
                return false
              }
              let key = sha256(canonical(candidate))
              let item = match cache.get(key) {
                Some(result) => {
                  hits += 1
                  result
                }
                None => {
                  let error = validate_ir(spec.input_ir, candidate)
                  validations += 1
                  let outcome = if error == c.expected {
                    let outcome = run_adapter(
                      spec,
                      {
                        index: c.index,
                        args: candidate,
                        category: c.category,
                        expected: c.expected,
                      },
                      adapter,
                    )
                    if outcome.called {
                      calls += 1
                    }
                    validations += validation_count(spec, outcome)
                    Some(outcome)
                  } else {
                    None
                  }
                  let result : CacheEntry = { input_error: error, outcome, }
                  cache[key] = result
                  result
                }
              }
              if item.input_error != c.expected {
                input_rejected += 1
                return false
              }
              if item.outcome is Some(outcome) &&
                outcome.failure == Some(signature) {
                trace.push({
                  "operator": operator,
                  "from": sha256(canonical(best)),
                  "to": key,
                  "before_nodes": nodes(best),
                  "after_nodes": nodes(candidate),
                  "before_bytes": byte_size(best),
                  "after_bytes": byte_size(candidate),
                  "signature": failure_json(signature),
                })
                best = candidate
                accepted = true
                return true
              }
              signature_rejected += 1
              false
            },
          ),
        )
        if !accepted {
          break
        }
      }
      if attempts >= budget {
        reason = "budget_exhausted"
      }
    }
  }
  {
    args: best,
    attempts,
    reason,
    adapter_calls: calls,
    validations,
    cache_hits: hits,
    rejected_input: input_rejected,
    rejected_signature: signature_rejected,
    rejected_size: size_rejected,
    trace,
  }
}

///|
pub fn shrink(
  spec : Spec,
  c : Case,
  version : String,
  budget~ : Int32 = 100,
) -> ShrinkResult {
  let reduced = shrink_adapter(
    spec,
    c,
    local_adapter(spec.adapter, version),
    budget~,
  )
  { args: reduced.args, attempts: reduced.attempts, reason: reduced.reason, }
}
