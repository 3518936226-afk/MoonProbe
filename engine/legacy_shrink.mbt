///|
fn legacy_shrink_candidates(v : Json) -> Array[Json] {
  let out : Array[Json] = []
  match v {
    Object(m) => {
      for k in keys(v) {
        let n = m.copy()
        n.remove(k)
        out.push(Json::object(n))
      }
      for k in keys(v) {
        for x in legacy_shrink_candidates(m[k]) {
          out.push(replace_key(v, k, x))
        }
      }
    }
    Array(a) => {
      out.push(Json::array([]))
      if a.length() > 1 {
        out.push(Json::array(a.iter().take(a.length() / 2).collect()))
      }
      for i = 0; i < a.length(); i = i + 1 {
        let n = a.copy()
        ignore(n.remove(i))
        out.push(Json::array(n))
        for x in legacy_shrink_candidates(a[i]) {
          let n = a.copy()
          n[i] = x
          out.push(Json::array(n))
        }
      }
    }
    String(s) => {
      let chars = s.iter().collect()
      out.push(Json::string(""))
      if chars.length() > 1 {
        out.push(
          Json::string(
            String::from_array(chars.iter().take(chars.length() / 2).collect()),
          ),
        )
      }
    }
    Number(n, ..) =>
      for x in [0.0, n / 2.0, (n / 2.0).floor(), (n / 2.0).ceil()] {
        out.push(Json::number(x))
      }
    True => out.push(Json::boolean(false))
    _ => ()
  }
  out
}

///|
pub fn shrink_legacy_adapter(
  spec : Spec,
  c : Case,
  adapter : Adapter,
  budget~ : Int32 = 100,
) -> ShrinkResult {
  guard run_adapter(spec, c, adapter).failure is Some(signature) else {
    return { args: c.args, attempts: 0, reason: "not_failure", }
  }
  if nodes(c.args) > 512 || byte_size(c.args) > 65536 {
    return { args: c.args, attempts: 0, reason: "input_budget", }
  }
  let mut best = c.args
  let mut attempts = 0
  while attempts < budget {
    let mut accepted = false
    for candidate in legacy_shrink_candidates(best) {
      if attempts >= budget {
        break
      }
      if !smaller(candidate, best) {
        continue
      }
      attempts += 1
      // Preserve the original input expectation before testing execution failures.
      if validate(spec.input, candidate) != c.expected {
        continue
      }
      let trial : Case = {
        index: c.index,
        args: candidate,
        category: c.category,
        expected: c.expected,
      }
      if run_adapter(spec, trial, adapter).failure == Some(signature) {
        best = candidate
        accepted = true
        break
      }
    }
    if !accepted {
      return {
        args: best,
        attempts,
        reason: if attempts >= budget {
          "budget_exhausted"
        } else {
          "local_minimum"
        },
      }
    }
  }
  { args: best, attempts, reason: "budget_exhausted", }
}

///|
pub fn shrink_legacy(
  spec : Spec,
  c : Case,
  version : String,
  budget~ : Int32 = 100,
) -> ShrinkResult {
  shrink_legacy_adapter(spec, c, local_adapter(spec.adapter, version), budget~)
}
