///|
pub(all) enum Shape {
  Obj(Array[(String, Schema)], Array[String], Bool)
  Arr(Schema, Int32, Int32?)
  Str(Int32, Int32?)
  Integral(Double?, Double?)
  Real(Double?, Double?)
  Boolean
  Nil
}

///|
pub(all) struct Schema {
  shape : Shape
  choices : Array[Json]?
  source_path : String
}

///|
fn bound(s : Json, k : String) -> Double? {
  if has(s, k) {
    Some(num(field(s, k)))
  } else {
    None
  }
}

///|
fn length_bound(s : Json, k : String) -> Int32? {
  bound(s, k).map(x => x.to_int())
}

///|
fn build_ir(s : Json, p : String) -> Schema {
  let shape = match text(field(s, "type")) {
    "object" => {
      let props = field(s, "properties")
      let children = keys(props).map(k => {
        (k, build_ir(field(props, k), ptr(ptr(p, "properties"), k)))
      })
      Obj(
        children,
        arr(field(s, "required")).map(text),
        field(s, "additionalProperties") != Json::boolean(false),
      )
    }
    "array" =>
      Arr(
        build_ir(field(s, "items"), ptr(p, "items")),
        num(field(s, "minItems")).to_int(),
        length_bound(s, "maxItems"),
      )
    "string" =>
      Str(num(field(s, "minLength")).to_int(), length_bound(s, "maxLength"))
    "integer" => Integral(bound(s, "minimum"), bound(s, "maximum"))
    "number" => Real(bound(s, "minimum"), bound(s, "maximum"))
    "boolean" => Boolean
    _ => Nil
  }
  {
    shape,
    choices: if has(s, "enum") {
      Some(arr(field(s, "enum")))
    } else {
      None
    },
    source_path: p,
  }
}

///|
pub fn compile_schema(s : Json) -> Schema raise ProbeError {
  check_schema(s, "", 1)
  build_ir(s, "")
}

///|
pub fn validate(s : Json, v : Json, path~ : String = "") -> Violation? {
  validate_ir(build_ir(s, ""), v, path~)
}

///|
pub fn validate_ir(s : Schema, v : Json, path~ : String = "") -> Violation? {
  let correct = match (s.shape, v) {
    (Obj(_, _, _), Object(_))
    | (Arr(_, _, _), Array(_))
    | (Str(_, _), String(_))
    | (Boolean, True)
    | (Boolean, False)
    | (Nil, Null) => true
    (Integral(_, _), Number(n, ..)) =>
      n.is_finite() && n.abs() <= 9007199254740991.0 && n.floor() == n
    (Real(_, _), Number(n, ..)) =>
      n.is_finite() && n.abs() <= 9007199254740991.0
    _ => false
  }
  if !correct {
    return Some({ code: "TYPE", path, })
  }
  if s.choices is Some(a) && !a.contains(v) {
    return Some({ code: "ENUM", path, })
  }
  match (s.shape, v) {
    (Obj(props, required, extra), Object(m)) => {
      for k in required {
        if !m.contains(k) {
          return Some({ code: "REQUIRED", path: ptr(path, k), })
        }
      }
      for k in keys(v) {
        let child = props.filter(x => x.0 == k).get(0)
        if child is Some((_, sub)) {
          if validate_ir(sub, m[k], path=ptr(path, k)) is Some(e) {
            return Some(e)
          }
        } else if !extra {
          return Some({ code: "ADDITIONAL_PROPERTIES", path: ptr(path, k), })
        }
      }
    }
    (Arr(sub, min, max), Array(a)) => {
      if a.length() < min {
        return Some({ code: "MIN_ITEMS", path, })
      }
      if max is Some(n) && a.length() > n {
        return Some({ code: "MAX_ITEMS", path, })
      }
      for i, x in a {
        if validate_ir(sub, x, path=ptr(path, i.to_string())) is Some(e) {
          return Some(e)
        }
      }
    }
    (Str(min, max), String(x)) => {
      let n = x.char_length()
      if n < min {
        return Some({ code: "MIN_LENGTH", path, })
      }
      if max is Some(m) && n > m {
        return Some({ code: "MAX_LENGTH", path, })
      }
    }
    (Integral(lo, hi), Number(x, ..)) | (Real(lo, hi), Number(x, ..)) => {
      if lo is Some(n) && x < n {
        return Some({ code: "MINIMUM", path, })
      }
      if hi is Some(n) && x > n {
        return Some({ code: "MAXIMUM", path, })
      }
    }
    _ => ()
  }
  None
}
