///|
fn baseline(s : Json, nonce : Int32) -> Json {
  if field(s, "enum") is Array(a) {
    return a[nonce % a.length()]
  }
  match text(field(s, "type")) {
    "object" => {
      let m : Map[String, Json] = Map([])
      let props = field(s, "properties")
      for k in keys(props) {
        m[k] = baseline(field(props, k), nonce)
      }
      Json::object(m)
    }
    "array" => {
      let min = num(field(s, "minItems")).to_int()
      let max = if has(s, "maxItems") {
        num(field(s, "maxItems")).to_int()
      } else {
        (min + 2).min(64)
      }
      let n = min + nonce % (max - min + 1)
      Json::array(Array::makei(n, _ => baseline(field(s, "items"), nonce)))
    }
    "string" => {
      let min = num(field(s, "minLength")).to_int()
      let max = if has(s, "maxLength") {
        num(field(s, "maxLength")).to_int()
      } else {
        (min + 12).min(1024)
      }
      Json::string(
        String::make(
          min + nonce % (max - min + 1),
          if nonce % 2 == 0 {
            'x'
          } else {
            '界'
          },
        ),
      )
    }
    "integer" | "number" => {
      let lo = if has(s, "minimum") {
        num(field(s, "minimum"))
      } else {
        -9007199254740991.0
      }
      let hi = if has(s, "maximum") {
        num(field(s, "maximum"))
      } else {
        9007199254740991.0
      }
      let x = (nonce % 11).to_double().max(lo).min(hi)
      Json::number(
        if text(field(s, "type")) == "integer" {
          x.ceil().min(hi.floor())
        } else {
          x
        },
      )
    }
    "boolean" => Json::boolean(nonce % 2 == 0)
    _ => Json::null()
  }
}

///|
fn replace_key(v : Json, k : String, x : Json) -> Json {
  let m = obj(v).copy()
  m[k] = x
  Json::object(m)
}

///|
fn variations(s : Json, base : Json) -> Array[Json] {
  let out : Array[Json] = [
    Json::null(),
    Json::boolean(true),
    Json::number(0.0),
    Json::string(""),
    Json::object(Map([])),
    Json::array([]),
  ]
  if field(s, "enum") is Array(a) {
    for e in a {
      out.push(e)
    }
    out.push(Json::string("__outside_enum__"))
  }
  match base {
    Object(m) => {
      for k in keys(base) {
        let removed = m.copy()
        removed.remove(k)
        out.push(Json::object(removed))
        let child = field(field(s, "properties"), k)
        for v in variations(child, m[k]) {
          out.push(replace_key(base, k, v))
        }
      }
      out.push(replace_key(base, "__extra__", Json::null()))
    }
    Array(a) => {
      for
        count in [
          0,
          num(field(s, "minItems")).to_int(),
          num(field(s, "maxItems")).to_int(),
          num(field(s, "maxItems")).to_int() + 1,
        ] {
        if count >= 0 && count <= 65 {
          out.push(
            Json::array(
              Array::makei(count, _ => baseline(field(s, "items"), 0)),
            ),
          )
        }
      }
      if !a.is_empty() {
        for v in variations(field(s, "items"), a[0]) {
          let b = a.copy()
          b[0] = v
          out.push(Json::array(b))
        }
      }
    }
    String(_) => {
      for
        count in [
          0,
          num(field(s, "minLength")).to_int() - 1,
          num(field(s, "minLength")).to_int(),
          num(field(s, "maxLength")).to_int(),
          num(field(s, "maxLength")).to_int() + 1,
        ] {
        if count >= 0 && count <= 1025 {
          out.push(Json::string(String::make(count, 'x')))
        }
      }
      out.push(Json::string("😀"))
    }
    Number(_, ..) => {
      for k in ["minimum", "maximum"] {
        if has(s, k) {
          let n = num(field(s, k))
          for d in [-1.0, 0.0, 1.0] {
            let x = n + d
            if x.abs() <= 9007199254740991.0 {
              out.push(Json::number(x))
            }
          }
        }
      }
      out.push(Json::number(0.5))
    }
    _ => ()
  }
  out
}

///|
pub fn generate(
  spec : Spec,
  seed : Int32,
  count : Int32,
) -> Array[Case] raise ProbeError {
  if count < 1 || count > 200 || seed < 0 {
    raise Invalid("cases must be 1..200 and seed 0..2147483647")
  }
  let base = baseline(spec.input, 0)
  if validate(spec.input, base) is Some(_) {
    raise Invalid("NO_GENERATABLE_SAMPLE")
  }
  let candidates : Array[(Json, String)] = [(base, "valid")]
  let variants = variations(spec.input, base)
  // Interleave positive boundary values and single mutations so both fit a small budget.
  let good = variants.filter(v => validate(spec.input, v) is None)
  let bad = variants.filter(v => validate(spec.input, v) is Some(_))
  let n = good.length().max(bad.length()).min(1000)
  for i = 0; i < n; i = i + 1 {
    if i < good.length() {
      candidates.push((good[i], "boundary"))
    }
    if i < bad.length() {
      candidates.push((bad[i], "invalid"))
    }
  }
  let out : Array[Case] = []
  let seen : Map[String, Bool] = Map([])
  for (v, category) in candidates {
    if out.length() >= count {
      break
    }
    let key = canonical(v)
    if !seen.contains(key) {
      seen[key] = true
      out.push({
        index: out.length(),
        args: v,
        category,
        expected: validate(spec.input, v),
      })
    }
  }
  let mut state = seed.reinterpret_as_uint() + 1U
  let mut attempts = 0
  while out.length() < count && attempts < 2000 {
    state = state ^ (state << 13)
    state = state ^ (state >> 17)
    state = state ^ (state << 5)
    let v = baseline(spec.input, (state % 1000000U).reinterpret_as_int())
    if validate(spec.input, v) is None {
      out.push({
        index: out.length(),
        args: v,
        category: "seeded",
        expected: None,
      })
    }
    attempts += 1
  }
  if out.length() != count {
    raise Invalid("GENERATION_BUDGET exhausted")
  }
  out
}
