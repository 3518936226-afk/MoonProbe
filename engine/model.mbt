///|
using @json {type Json}

///|
pub(all) suberror ProbeError {
  Invalid(String)
}

///|
pub(all) struct Spec {
  name : String
  input : Json
  input_ir : Schema
  output_ir : Schema?
  output : Json?
  adapter : String
  fingerprint : String
}

///|
#derive(Eq)
pub(all) struct Violation {
  code : String
  path : String
}

///|
pub(all) struct Case {
  index : Int32
  args : Json
  category : String
  expected : Violation?
}

///|
#derive(Eq)
pub(all) struct Failure {
  stage : String
  code : String
  path : String
}

///|
pub(all) struct Outcome {
  failure : Failure?
  called : Bool
}

///|
pub(all) struct ShrinkResult {
  args : Json
  attempts : Int32
  reason : String
}

///|
pub fn obj(j : Json) -> Map[String, Json] {
  match j {
    Object(m) => m
    _ => Map([])
  }
}

///|
pub fn arr(j : Json) -> Array[Json] {
  match j {
    Array(a) => a
    _ => []
  }
}

///|
pub fn field(j : Json, key : String) -> Json {
  obj(j).get(key).unwrap_or(Json::null())
}

///|
pub fn text(j : Json) -> String {
  match j {
    String(s) => s
    _ => ""
  }
}

///|
pub fn num(j : Json) -> Double {
  match j {
    Number(n, ..) => n
    _ => 0.0
  }
}

///|
fn keys(j : Json) -> Array[String] {
  let a = obj(j).keys().collect()
  a.sort_by((x, y) => x.lexical_compare(y))
  a
}

///|
fn ptr(p : String, key : String) -> String {
  p + "/" + key.replace(old="~", new="~0").replace(old="/", new="~1")
}

///|
pub fn canonical(j : Json) -> String {
  match j {
    Object(m) => {
      let parts : Array[String] = []
      for k in keys(j) {
        parts.push(Json::string(k).stringify() + ":" + canonical(m[k]))
      }
      "{" + parts.join(",") + "}"
    }
    Array(a) => "[" + a.map(canonical).join(",") + "]"
    Number(n, ..) => Json::number(if n == 0.0 { 0.0 } else { n }).stringify()
    _ => j.stringify()
  }
}

///|
pub fn byte_size(j : Json) -> Int32 {
  @utf8.encode(canonical(j)).length()
}

///|
pub fn nodes(j : Json) -> Int32 {
  match j {
    Object(m) => 1 + m.values().fold(init=0, (n, x) => n + nodes(x))
    Array(a) => 1 + a.fold(init=0, (n, x) => n + nodes(x))
    _ => 1
  }
}

///|
fn smaller(a : Json, b : Json) -> Bool {
  nodes(a) < nodes(b) || (nodes(a) == nodes(b) && byte_size(a) < byte_size(b))
}

///|
fn semantic(s : Json) -> Json {
  let out : Map[String, Json] = Map([])
  for k in keys(s) {
    if k == "title" || k == "description" {
      continue
    }
    if k == "properties" {
      let props : Map[String, Json] = Map([])
      for name in keys(field(s, k)) {
        props[name] = semantic(field(field(s, k), name))
      }
      out[k] = Json::object(props)
    } else if k == "items" {
      out[k] = semantic(field(s, k))
    } else {
      out[k] = field(s, k)
    }
  }
  Json::object(out)
}

///|
pub fn failure_json(f : Failure) -> Json {
  { "stage": f.stage, "code": f.code, "path": f.path }
}

///|
pub fn expected_json(v : Violation?) -> Json {
  match v {
    None => Json::null()
    Some(v) => { "code": v.code, "path": v.path }
  }
}

///|
pub fn case_json(c : Case, seed : Int32) -> Json {
  {
    "index": c.index,
    "args": c.args,
    "category": c.category,
    "seed": seed,
    "expected": expected_json(c.expected),
  }
}
