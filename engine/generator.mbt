///|
pub(all) struct Generation {
  cases : Array[Case]
  coverage : Json
  visited : Int32
  duplicates : Int32
  termination : String
}

///|
priv struct Job {
  id : String
  schema_path : String
  path : String
  rule : String
  kind : String
  expected : Violation?
  make : () -> Json
}

///|
priv struct Task {
  schema : Schema
  trail : Array[String]
  context : Json
}

///|
fn replace_key(v : Json, k : String, x : Json) -> Json {
  let m = obj(v).copy()
  m[k] = x
  Json::object(m)
}

///|
fn index_of(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    n = n * 10 + c.to_int() - 48
  }
  n
}

///|
fn at_path(v : Json, trail : Array[String], i : Int32, x : Json) -> Json {
  if i == trail.length() {
    return x
  }
  match v {
    Object(m) => replace_key(v, trail[i], at_path(m[trail[i]], trail, i + 1, x))
    Array(a) => {
      let n = a.copy()
      let k = index_of(trail[i])
      n[k] = at_path(a[k], trail, i + 1, x)
      Json::array(n)
    }
    _ => v
  }
}

///|
fn get_path(v : Json, trail : Array[String]) -> Json {
  let mut x = v
  for k in trail {
    x = match x {
      Array(a) => a[index_of(k)]
      _ => field(x, k)
    }
  }
  x
}

///|
fn path_text(trail : Array[String]) -> String {
  trail.fold(init="", (s, k) => ptr(s, k))
}

///|
fn child_trail(t : Array[String], k : String) -> Array[String] {
  let n = t.copy()
  n.push(k)
  n
}

///|
fn stream(seed : Int32, index : Int32, p : String) -> UInt32 {
  let mut n = 2166136261U ^
    seed.reinterpret_as_uint() ^
    (index.reinterpret_as_uint() * 2654435761U)
  for b in @utf8.encode(p) {
    n = (n ^ b.to_uint()) * 16777619U
  }
  n = n ^ (n >> 16)
  n = n * 2246822519U
  n = n ^ (n >> 13)
  n = n * 3266489917U
  n ^ (n >> 16)
}

///|
fn sample(s : Schema, seed : Int32, index : Int32, p : String) -> Json {
  let n = if index == 0 { 0U } else { stream(seed, index, p) }
  if s.choices is Some(a) {
    return a[(n % a.length().reinterpret_as_uint()).reinterpret_as_int()]
  }
  match s.shape {
    Obj(props, required, _) => {
      let m : Map[String, Json] = Map([])
      for (k, sub) in props {
        if index == 0 ||
          required.contains(k) ||
          (stream(seed, index, ptr(p, k)) & 1U) == 0U {
          m[k] = sample(sub, seed, index, ptr(p, k))
        }
      }
      Json::object(m)
    }
    Arr(sub, min, max) => {
      let cap = max.unwrap_or((min + 3).min(64))
      let count = min +
        (n % (cap - min + 1).reinterpret_as_uint()).reinterpret_as_int()
      Json::array(
        Array::makei(count, i => sample(sub, seed, index, ptr(p, i.to_string()))),
      )
    }
    Str(min, max) => {
      let cap = max.unwrap_or((min + 12).min(1024))
      let count = min +
        (n % (cap - min + 1).reinterpret_as_uint()).reinterpret_as_int()
      let chars = ['x', '界', '😀', 'y', '\n']
      Json::string(String::make(count, chars[(n % 5U).reinterpret_as_int()]))
    }
    Integral(lo, hi) | Real(lo, hi) => {
      let low = lo.unwrap_or(-1000.0)
      let high = hi.unwrap_or(1000.0)
      let lower = if lo is None { low.min(high) } else { low }
      let upper = if hi is None { high.max(lower) } else { high }
      let x = if index == 0 {
        0.0.max(lower).min(upper)
      } else {
        (lower + (upper - lower) * (n.to_double() / 4294967295.0))
        .max(lower)
        .min(upper)
      }
      match s.shape {
        Integral(_, _) =>
          Json::number(x.floor().max(lower.ceil()).min(upper.floor()))
        _ => Json::number(x)
      }
    }
    Boolean => Json::boolean(n % 2U == 0U)
    Nil => Json::null()
  }
}

///|
pub fn next_float(n : Double, up : Bool) -> Double {
  if n == 0.0 {
    return if up {
      1UL.reinterpret_as_double()
    } else {
      -1UL.reinterpret_as_double()
    }
  }
  let bits = n.reinterpret_as_uint64()
  (if (n > 0.0) == up { bits + 1UL } else { bits - 1UL }).reinterpret_as_double()
}

///|
fn goal_id(source : String, p : String, rule : String, kind : String) -> String {
  let key : Json = {
    "schema_path": source,
    "path": p,
    "rule": rule,
    "kind": kind,
  }
  sha256(canonical(key))
}

///|
fn offer(
  jobs : Array[Job],
  s : Schema,
  trail : Array[String],
  context : Json,
  value : Json,
  rule : String,
  kind : String,
  negative : Bool,
) -> Unit {
  let p = path_text(trail)
  let expected = if negative { Some({ code: rule, path: p, }) } else { None }
  jobs.push({
    id: goal_id(s.source_path, p, rule, kind),
    schema_path: s.source_path,
    path: p,
    rule,
    kind,
    expected,
    make: () => at_path(context, trail, 0, value),
  })
}

///|
fn jobs_for(spec : Spec) -> (Array[Job], Array[Json]) {
  let jobs : Array[Job] = []
  let excluded : Array[Json] = []
  let base = sample(spec.input_ir, 0, 0, "")
  let tasks : Array[Task] = [
    { schema: spec.input_ir, trail: [], context: base, },
  ]
  let mut cursor = 0
  while cursor < tasks.length() {
    let { schema: s, trail, context, } = tasks[cursor]
    cursor += 1
    let value = get_path(context, trail)
    offer(jobs, s, trail, context, value, "ACCEPT", "baseline", false)
    offer(
      jobs,
      s,
      trail,
      context,
      match s.shape {
        Nil => Json::boolean(true)
        _ => Json::null()
      },
      "TYPE",
      "wrong_type",
      true,
    )
    if s.choices is Some(a) {
      for i, v in a {
        offer(
          jobs,
          s,
          trail,
          context,
          v,
          "ENUM",
          "member_" + i.to_string(),
          false,
        )
      }
      let mut outside : Json? = None
      let plain : Schema = {
        shape: s.shape,
        properties: s.properties,
        choices: None,
        source_path: s.source_path,
      }
      for i = 0; i < 128; i = i + 1 {
        let v = sample(plain, 19, i, path_text(trail))
        if !a.contains(v) {
          outside = Some(v)
          break
        }
      }
      if outside is Some(v) {
        offer(jobs, s, trail, context, v, "ENUM", "outside", true)
      } else {
        let enum_values : Map[String, Bool] = Map([])
        for v in a {
          enum_values[canonical(v)] = true
        }
        let proven = finite_size(plain) is Some(n) && enum_values.length() == n
        excluded.push({
          "schema_path": s.source_path,
          "path": path_text(trail),
          "rule": "ENUM",
          "kind": "outside",
          "status": if proven {
            "not_applicable"
          } else {
            "uncovered"
          },
          "reason": "no_complement_found_in_128_candidates",
        })
      }
    }
    match s.shape {
      Obj(props, required, extra) => {
        for (k, sub) in props {
          let changed = obj(value).copy()
          changed.remove(k)
          if required.contains(k) {
            let t = child_trail(trail, k)
            let p = path_text(t)
            jobs.push({
              id: goal_id(s.source_path, p, "REQUIRED", "missing"),
              schema_path: sub.source_path,
              path: p,
              rule: "REQUIRED",
              kind: "missing",
              expected: Some({ code: "REQUIRED", path: p, }),
              make: () => at_path(context, trail, 0, Json::object(changed)),
            })
          } else {
            offer(
              jobs,
              s,
              trail,
              context,
              Json::object(changed),
              "OPTIONAL",
              "absent_" + k,
              false,
            )
          }
          tasks.push({ schema: sub, trail: child_trail(trail, k), context, })
        }
        if !extra {
          let mut key = "__extra__"
          while obj(value).contains(key) {
            key = key + "_"
          }
          let p = ptr(path_text(trail), key)
          jobs.push({
            id: goal_id(s.source_path, p, "ADDITIONAL_PROPERTIES", "extra"),
            schema_path: s.source_path,
            path: p,
            rule: "ADDITIONAL_PROPERTIES",
            kind: "extra",
            expected: Some({ code: "ADDITIONAL_PROPERTIES", path: p, }),
            make: () => {
              at_path(context, trail, 0, replace_key(value, key, Json::null()))
            },
          })
        }
      }
      Arr(sub, min, max) => {
        for count in [min, max.unwrap_or((min + 3).min(64))] {
          let v = Json::array(
            Array::makei(count, i => sample(sub, 0, 0, i.to_string())),
          )
          offer(
            jobs,
            s,
            trail,
            context,
            v,
            "LENGTH",
            "valid_" + count.to_string(),
            false,
          )
        }
        if min > 0 {
          offer(
            jobs,
            s,
            trail,
            context,
            Json::array(Array::makei(min - 1, _ => sample(sub, 0, 0, ""))),
            "MIN_ITEMS",
            "below",
            true,
          )
        }
        if max is Some(n) {
          offer(
            jobs,
            s,
            trail,
            context,
            Json::array(Array::makei(n + 1, _ => sample(sub, 0, 0, ""))),
            "MAX_ITEMS",
            "above",
            true,
          )
        }
        let count = min.max(3).min(max.unwrap_or(64))
        if count > 0 {
          let v = Json::array(
            Array::makei(count, i => sample(sub, 0, 0, i.to_string())),
          )
          let expanded = at_path(context, trail, 0, v)
          let positions = [0, count / 2, count - 1]
          let seen : Map[Int32, Bool] = Map([])
          for i in positions {
            if !seen.contains(i) {
              seen[i] = true
              tasks.push({
                schema: sub,
                trail: child_trail(trail, i.to_string()),
                context: expanded,
              })
            }
          }
        } else {
          excluded.push({
            "schema_path": sub.source_path,
            "rule": "ITEMS",
            "status": "not_applicable",
            "reason": "maxItems_zero",
          })
        }
      }
      Str(min, max) => {
        for length in [min, max.unwrap_or((min + 12).min(1024))] {
          let v = Json::string(String::make(length, 'x'))
          if validate_ir(s, v) is None {
            offer(
              jobs,
              s,
              trail,
              context,
              v,
              "LENGTH",
              "valid_" + length.to_string(),
              false,
            )
          } else {
            excluded.push({
              "schema_path": s.source_path,
              "rule": "LENGTH",
              "kind": "valid_" + length.to_string(),
              "status": "not_applicable",
              "reason": "excluded_by_enum",
            })
          }
        }
        if s.choices is None {
          if min > 0 {
            offer(
              jobs,
              s,
              trail,
              context,
              Json::string(String::make(min - 1, 'x')),
              "MIN_LENGTH",
              "below",
              true,
            )
          }
          if max is Some(n) {
            offer(
              jobs,
              s,
              trail,
              context,
              Json::string(String::make(n + 1, 'x')),
              "MAX_LENGTH",
              "above",
              true,
            )
          }
        } else {
          excluded.push({
            "schema_path": s.source_path,
            "rule": "LENGTH_NEGATIVE",
            "status": "not_applicable",
            "reason": "enum_has_priority",
          })
        }
      }
      Integral(lo, hi) | Real(lo, hi) =>
        for (label, b) in [("MINIMUM", lo), ("MAXIMUM", hi)] {
          if b is Some(n) {
            let integer = match s.shape {
              Integral(_, _) => true
              _ => false
            }
            let edge = if integer {
              if label == "MINIMUM" {
                n.ceil()
              } else {
                n.floor()
              }
            } else {
              n
            }
            let legal = Json::number(edge)
            if validate_ir(s, legal) is None {
              offer(jobs, s, trail, context, legal, label, "endpoint", false)
            } else {
              excluded.push({
                "schema_path": s.source_path,
                "rule": label,
                "kind": "endpoint",
                "status": "not_applicable",
                "reason": "excluded_by_enum",
              })
            }
            if s.choices is None {
              let bad = if integer {
                if label == "MINIMUM" {
                  edge - 1.0
                } else {
                  edge + 1.0
                }
              } else {
                next_float(n, label == "MAXIMUM")
              }
              if bad.abs() <= 9007199254740991.0 {
                offer(
                  jobs,
                  s,
                  trail,
                  context,
                  Json::number(bad),
                  label,
                  "outside",
                  true,
                )
              }
            } else {
              excluded.push({
                "schema_path": s.source_path,
                "rule": label,
                "kind": "outside",
                "status": "not_applicable",
                "reason": "enum_has_priority",
              })
            }
          }
        }
      _ => ()
    }
    if jobs.length() > 2000 || tasks.length() > 512 {
      break
    }
  }
  // Pairwise optional presence follows unary obligations.
  for task in tasks {
    if task.schema.shape is Obj(props, required, _) {
      let optional = props.filter(x => !required.contains(x.0))
      if optional.length() > 8 {
        excluded.push({
          "schema_path": task.schema.source_path,
          "rule": "PAIRWISE",
          "status": "uncovered",
          "reason": "more_than_8_optional_siblings",
        })
        continue
      }
      let parent = get_path(task.context, task.trail)
      for i = 0; i < optional.length(); i = i + 1 {
        for j = i + 1; j < optional.length(); j = j + 1 {
          for state = 0; state < 4; state = state + 1 {
            let m = obj(parent).copy()
            if state % 2 == 0 {
              m.remove(optional[i].0)
            }
            if state / 2 == 0 {
              m.remove(optional[j].0)
            }
            offer(
              jobs,
              task.schema,
              task.trail,
              task.context,
              Json::object(m),
              "PAIRWISE",
              optional[i].0 + ":" + optional[j].0 + ":" + state.to_string(),
              false,
            )
          }
        }
      }
    }
    if jobs.length() > 2000 {
      break
    }
  }
  (jobs, excluded)
}

///|
pub fn generate_result(
  spec : Spec,
  seed : Int32,
  count : Int32,
) -> Generation raise ProbeError {
  if count < 1 || count > 200 || seed < 0 {
    raise Invalid("cases must be 1..200 and seed nonnegative")
  }
  let (raw_jobs, raw_excluded) = jobs_for(spec)
  let jobs : Array[Job] = []
  let ids : Map[String, Bool] = Map([])
  for job in raw_jobs {
    if !ids.contains(job.id) {
      ids[job.id] = true
      jobs.push(job)
    }
  }
  let excluded : Array[Json] = []
  let facts : Map[String, Bool] = Map([])
  for fact in raw_excluded {
    let key = canonical(fact)
    if !facts.contains(key) {
      facts[key] = true
      excluded.push(fact)
    }
  }
  if jobs.length() > 2000 {
    raise Invalid("GOAL_BUDGET exceeds 2000 obligations")
  }
  let out : Array[Case] = []
  let goals : Array[Json] = []
  let seen : Map[String, Int32] = Map([])
  let mut visited = 0
  let mut duplicates = 0
  let mut covered = 0
  // Round-robin by goal depth keeps deep nodes from starving sibling paths.
  let queues : Map[String, Array[Job]] = Map([])
  let order : Array[String] = []
  let unary = jobs.filter(j => j.rule != "PAIRWISE")
  for j in unary {
    let key = j.path
    if !queues.contains(key) {
      queues[key] = []
      order.push(key)
    }
    queues[key].push(j)
  }
  let schedule : Array[Job] = []
  let mut round = 0
  while schedule.length() < unary.length() {
    for p in order {
      if queues[p].get(round) is Some(j) {
        schedule.push(j)
      }
    }
    round += 1
  }
  for job in jobs.filter(j => j.rule == "PAIRWISE") {
    schedule.push(job)
  }
  for job in schedule {
    let mut hit : Int32? = None
    if visited < 2000 {
      visited += 1
      let v = (job.make)()
      if nodes(v) > 512 || byte_size(v) > 65536 {
        goals.push({
          "id": job.id,
          "schema_path": job.schema_path,
          "path": job.path,
          "rule": job.rule,
          "kind": job.kind,
          "status": "uncovered",
          "reason": "case_resource_budget",
          "case_index": null,
        })
        continue
      }
      let observed = validate_ir(spec.input_ir, v)
      if observed != job.expected {
        raise Invalid("ENGINE_EXPECTATION_MISMATCH " + job.id)
      }
      let key = canonical(v)
      if seen.get(key) is Some(i) {
        duplicates += 1
        hit = Some(i)
      } else if out.length() < count {
        let i = out.length()
        seen[key] = i
        hit = Some(i)
        out.push({
          index: i,
          args: v,
          category: if job.expected is Some(_) {
            "invalid"
          } else if job.kind == "baseline" {
            "valid"
          } else {
            "boundary"
          },
          expected: job.expected,
        })
      }
    }
    if hit is Some(_) {
      covered += 1
    }
    goals.push({
      "id": job.id,
      "schema_path": job.schema_path,
      "path": job.path,
      "rule": job.rule,
      "kind": job.kind,
      "expected": expected_json(job.expected),
      "status": if hit is Some(_) {
        "covered"
      } else {
        "uncovered"
      },
      "case_index": hit
      .map(i => Json::number(i.to_double()))
      .unwrap_or(Json::null()),
    })
  }
  let domain = finite_size(spec.input_ir)
  let mut legal = out.filter(c => c.expected is None).length()
  let mut index = 1
  while out.length() < count &&
        visited < 2000 &&
        !(domain is Some(n) && legal >= n) {
    visited += 1
    let v = sample(spec.input_ir, seed, index, "")
    index += 1
    if validate_ir(spec.input_ir, v) is Some(_) {
      raise Invalid("ENGINE_EXPECTATION_MISMATCH seeded")
    }
    let key = canonical(v)
    if seen.contains(key) {
      duplicates += 1
      continue
    }
    seen[key] = out.length()
    out.push({
      index: out.length(),
      args: v,
      category: "seeded",
      expected: None,
    })
    legal += 1
  }
  let space_exhausted = domain is Some(n) && legal >= n
  let uncovered_excluded = excluded
    .filter(x => text(field(x, "status")) == "uncovered")
    .length()
  let term = if out.length() >= count {
    "case_limit"
  } else if space_exhausted {
    "space_exhausted"
  } else {
    "budget_exhausted"
  }
  {
    cases: out,
    coverage: {
      "targets": goals,
      "excluded": excluded,
      "covered": covered,
      "total": jobs.length() + excluded.length(),
      "eligible": jobs.length() + uncovered_excluded,
      "not_applicable": excluded.length() - uncovered_excluded,
      "uncovered": jobs.length() - covered + uncovered_excluded,
      "complete": covered == jobs.length() && uncovered_excluded == 0,
    },
    visited,
    duplicates,
    termination: term,
  }
}

///|
pub fn generate(
  spec : Spec,
  seed : Int32,
  count : Int32,
) -> Array[Case] raise ProbeError {
  generate_result(spec, seed, count).cases
}

///|
fn finite_size(s : Schema) -> Int32? {
  if s.choices is Some(values) {
    let seen : Map[String, Bool] = Map([])
    for v in values {
      seen[canonical(v)] = true
    }
    return Some(seen.length())
  }
  match s.shape {
    Boolean => Some(2)
    Nil => Some(1)
    Str(0, Some(0)) => Some(1)
    Integral(Some(lo), Some(hi)) => {
      let n = hi.floor() - lo.ceil() + 1.0
      if n <= 200.0 {
        Some(n.to_int())
      } else {
        None
      }
    }
    Real(Some(lo), Some(hi)) => if lo == hi { Some(1) } else { None }
    Obj(props, required, false) => {
      let mut n = 1
      for (k, sub) in props {
        guard finite_size(sub) is Some(c) else { return None }
        n *= c + (if required.contains(k) { 0 } else { 1 })
        if n > 200 {
          return None
        }
      }
      Some(n)
    }
    Arr(sub, min, Some(max)) => {
      guard finite_size(sub) is Some(c) else {
        return if max == 0 { Some(1) } else { None }
      }
      let mut count = 0
      let mut power = 1
      for i = 0; i <= max; i = i + 1 {
        if i >= min {
          count += power
        }
        if count > 200 {
          return None
        }
        if i < max {
          power *= c
          if power > 200 {
            return None
          }
        }
      }
      Some(count)
    }
    _ => None
  }
}
