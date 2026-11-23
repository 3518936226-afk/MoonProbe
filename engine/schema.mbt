///|
fn invalid(path : String, message : String) -> Unit raise ProbeError {
  raise Invalid(path + ": " + message)
}

///|
fn has(j : Json, key : String) -> Bool {
  obj(j).contains(key)
}

///|
fn type_is(t : String, j : Json) -> Bool {
  match (t, j) {
    ("object", Object(_)) | ("array", Array(_)) | ("string", String(_)) => true
    ("number", Number(n, ..)) => n.is_finite() && n.abs() <= 9007199254740991.0
    ("integer", Number(n, ..)) =>
      n.is_finite() && n.abs() <= 9007199254740991.0 && n.floor() == n
    ("boolean", True) | ("boolean", False) | ("null", Null) => true
    _ => false
  }
}

///|
fn nonneg(
  j : Json,
  key : String,
  p : String,
  capacity : Int32,
) -> Unit raise ProbeError {
  if has(j, key) {
    let value = field(j, key)
    if !type_is("integer", value) ||
      num(value) < 0.0 ||
      num(value) > capacity.to_double() {
      invalid(
        ptr(p, key),
        "expected non-negative integer within generation capacity",
      )
    }
  }
}

///|
fn check_schema(s : Json, p : String, depth : Int32) -> Unit raise ProbeError {
  if depth > 8 {
    invalid(p, "SCHEMA_DEPTH exceeds 8")
  }
  guard s is Object(_) else {
    invalid(p, "Schema must be an object")
    return
  }
  let t = text(field(s, "type"))
  if !["object", "array", "string", "integer", "number", "boolean", "null"].contains(
      t,
    ) {
    invalid(ptr(p, "type"), "one explicit supported type is required")
  }
  let common = ["type", "title", "description", "enum"]
  let specific = match t {
    "object" => ["properties", "required", "additionalProperties"]
    "array" => ["items", "minItems", "maxItems"]
    "string" => ["minLength", "maxLength"]
    "number" | "integer" => ["minimum", "maximum"]
    _ => []
  }
  for k in keys(s) {
    if !common.contains(k) && !specific.contains(k) {
      invalid(ptr(p, k), "UNSUPPORTED_KEYWORD")
    }
  }
  for k in ["title", "description"] {
    if has(s, k) && !type_is("string", field(s, k)) {
      invalid(ptr(p, k), "expected string")
    }
  }
  match t {
    "object" => {
      let props = field(s, "properties")
      if has(s, "properties") {
        guard props is Object(_) else {
          invalid(ptr(p, "properties"), "expected object")
          return
        }
      }
      let req = field(s, "required")
      if has(s, "required") {
        guard req is Array(a) else {
          invalid(ptr(p, "required"), "expected string array")
          return
        }
        let seen : Array[String] = []
        for v in a {
          let key = text(v)
          if !type_is("string", v) || !has(props, key) || seen.contains(key) {
            invalid(
              ptr(p, "required"),
              "required must contain distinct declared properties",
            )
          }
          seen.push(key)
        }
      }
      if has(s, "additionalProperties") &&
        !type_is("boolean", field(s, "additionalProperties")) {
        invalid(ptr(p, "additionalProperties"), "expected boolean")
      }
      for k in keys(props) {
        check_schema(field(props, k), ptr(ptr(p, "properties"), k), depth + 1)
      }
    }
    "array" => {
      check_schema(field(s, "items"), ptr(p, "items"), depth + 1)
      nonneg(s, "minItems", p, 64)
      nonneg(s, "maxItems", p, 64)
      if has(s, "maxItems") &&
        num(field(s, "minItems")) > num(field(s, "maxItems")) {
        invalid(p, "contradictory array bounds")
      }
    }
    "string" => {
      nonneg(s, "minLength", p, 1024)
      nonneg(s, "maxLength", p, 1024)
      if has(s, "maxLength") &&
        num(field(s, "minLength")) > num(field(s, "maxLength")) {
        invalid(p, "contradictory string bounds")
      }
    }
    "integer" | "number" => {
      for k in ["minimum", "maximum"] {
        if has(s, k) && !type_is("number", field(s, k)) {
          invalid(ptr(p, k), "numeric bound exceeds supported finite range")
        }
      }
      if has(s, "minimum") &&
        has(s, "maximum") &&
        num(field(s, "minimum")) > num(field(s, "maximum")) {
        invalid(p, "contradictory numeric bounds")
      }
      if t == "integer" &&
        has(s, "minimum") &&
        has(s, "maximum") &&
        num(field(s, "minimum")).ceil() > num(field(s, "maximum")).floor() {
        invalid(p, "no integer in interval")
      }
    }
    _ => ()
  }
  if has(s, "enum") {
    guard field(s, "enum") is Array(a) else {
      invalid(ptr(p, "enum"), "expected scalar array")
      return
    }
    if a.is_empty() || a.length() > 64 || t == "array" || t == "object" {
      invalid(ptr(p, "enum"), "non-empty scalar enum required")
    }
    let plain = obj(s).copy()
    plain.remove("enum")
    for e in a {
      if legacy_validate(Json::object(plain), e) is Some(_) {
        invalid(ptr(p, "enum"), "enum member violates declared type or bounds")
      }
    }
  }
}

///|
pub fn legacy_validate(
  s : Json,
  value : Json,
  path~ : String = "",
) -> Violation? {
  let t = text(field(s, "type"))
  if !type_is(t, value) {
    return Some({ code: "TYPE", path, })
  }
  if has(s, "enum") && !arr(field(s, "enum")).contains(value) {
    return Some({ code: "ENUM", path, })
  }
  match value {
    Object(m) => {
      for v in arr(field(s, "required")) {
        let k = text(v)
        if !m.contains(k) {
          return Some({ code: "REQUIRED", path: ptr(path, k), })
        }
      }
      let props = field(s, "properties")
      for k in keys(value) {
        if has(props, k) {
          if legacy_validate(field(props, k), m[k], path=ptr(path, k))
            is Some(v) {
            return Some(v)
          }
        } else if field(s, "additionalProperties") == Json::boolean(false) {
          return Some({ code: "ADDITIONAL_PROPERTIES", path: ptr(path, k), })
        }
      }
    }
    Array(a) => {
      if a.length().to_double() < num(field(s, "minItems")) {
        return Some({ code: "MIN_ITEMS", path, })
      }
      if has(s, "maxItems") &&
        a.length().to_double() > num(field(s, "maxItems")) {
        return Some({ code: "MAX_ITEMS", path, })
      }
      for i, v in a {
        if legacy_validate(field(s, "items"), v, path=ptr(path, i.to_string()))
          is Some(e) {
          return Some(e)
        }
      }
    }
    String(v) => {
      let n = v.char_length().to_double()
      if n < num(field(s, "minLength")) {
        return Some({ code: "MIN_LENGTH", path, })
      }
      if has(s, "maxLength") && n > num(field(s, "maxLength")) {
        return Some({ code: "MAX_LENGTH", path, })
      }
    }
    Number(n, ..) => {
      if has(s, "minimum") && n < num(field(s, "minimum")) {
        return Some({ code: "MINIMUM", path, })
      }
      if has(s, "maximum") && n > num(field(s, "maximum")) {
        return Some({ code: "MAXIMUM", path, })
      }
    }
    _ => ()
  }
  None
}

///|
pub fn load_spec(j : Json) -> Spec raise ProbeError {
  guard j is Object(_) else { raise Invalid("ToolSpec must be an object") }
  for k in keys(j) {
    if !["name", "input_schema", "output_schema", "adapter_id"].contains(k) {
      invalid(ptr("", k), "unknown ToolSpec field")
    }
  }
  let name = text(field(j, "name"))
  let adapter = text(field(j, "adapter_id"))
  if name == "" {
    invalid("/name", "nonempty tool name required")
  }
  if !["extract_deadline", "echo"].contains(adapter) {
    invalid("/adapter_id", "unregistered local adapter")
  }
  let input = field(j, "input_schema")
  check_schema(input, "/input_schema", 1)
  if text(field(input, "type")) != "object" {
    invalid("/input_schema/type", "input root must be object")
  }
  let output = if has(j, "output_schema") {
    let s = field(j, "output_schema")
    check_schema(s, "/output_schema", 1)
    Some(s)
  } else {
    None
  }
  let (node_budget, byte_budget) = expansion_cost(input)
  if node_budget > 512 || byte_budget > 65536 {
    invalid(
      "/input_schema", "GENERATION_CAPACITY expanded sample exceeds 512 nodes or 65536 bytes",
    )
  }
  let semantics : Json = {
    "name": name,
    "input_schema": semantic(input),
    "output_schema": output.map(semantic).unwrap_or(Json::null()),
  }
  {
    name,
    input,
    output,
    input_ir: build_ir(input, "/input_schema"),
    output_ir: output.map(s => build_ir(s, "/output_schema")),
    adapter,
    fingerprint: sha256(canonical(semantics)),
  }
}

///|
fn expansion_cost(s : Json) -> (Int32, Int32) {
  match text(field(s, "type")) {
    "object" => {
      let mut n = 1
      let mut b = 2
      for k in keys(field(s, "properties")) {
        let (cn, cb) = expansion_cost(field(field(s, "properties"), k))
        n = (n + cn).min(513)
        b = (b + cb + @utf8.encode(k).length() * 6 + 4).min(65537)
      }
      (n, b)
    }
    "array" => {
      let count = if has(s, "maxItems") {
        num(field(s, "maxItems")).to_int()
      } else {
        (num(field(s, "minItems")).to_int() + 2).min(64)
      }
      let (n, b) = expansion_cost(field(s, "items"))
      ((1 + count * n).min(513), (2 + count * (b + 1)).min(65537))
    }
    "string" => {
      let max = if has(s, "maxLength") {
        num(field(s, "maxLength")).to_int()
      } else {
        (num(field(s, "minLength")).to_int() + 12).min(1024)
      }
      let mut b = max * 6 + 2
      for v in arr(field(s, "enum")) {
        b = b.max(byte_size(v))
      }
      (1, b.min(65537))
    }
    _ => (1, 32)
  }
}
