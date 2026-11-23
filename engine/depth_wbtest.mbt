///|
test "D01 typed IR preserves v1 fingerprint" {
  let j : Json = {
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "x": { "type": "integer", "minimum": 2 } },
      "required": ["x"],
    },
  }
  let spec = load_spec(j)
  assert_true(validate_ir(spec.input_ir, { "x": 2 }) is None)
  assert_true(
    validate_ir(spec.input_ir, { "x": 1 }) ==
    Some({ code: "MINIMUM", path: "/x", }),
  )
  assert_true(
    validate_ir(spec.input_ir, { "x": 2.5 }) ==
    Some({ code: "TYPE", path: "/x", }),
  )
  let semantic_json : Json = {
    "name": "echo",
    "input_schema": semantic(spec.input),
    "output_schema": null,
  }
  @debug.assert_eq(spec.fingerprint, sha256(canonical(semantic_json)))
}

///|
test "D02 generation unique finite spaces and full catalogue" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "b": { "type": "boolean" } },
      "required": ["b"],
      "additionalProperties": false,
    },
  })
  let g = generate_result(spec, 9, 200)
  let seen : Map[String, Bool] = Map([])
  for c in g.cases {
    assert_false(seen.contains(canonical(c.args)))
    seen[canonical(c.args)] = true
    assert_true(validate_ir(spec.input_ir, c.args) == c.expected)
  }
  @debug.assert_eq(g.termination, "space_exhausted")
  assert_true(g.cases.length() < 200)
  assert_true(field(g.coverage, "complete") == Json::boolean(true))
  let tiny = generate_result(spec, 9, 1)
  assert_true(field(tiny.coverage, "complete") == Json::boolean(false))
}

///|
test "D03 optional pairwise and independent array streams" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "a": { "type": "boolean" },
        "b": { "type": "boolean" },
        "c": { "type": "boolean" },
      },
      "additionalProperties": false,
    },
  })
  let g = generate_result(spec, 9, 200)
  for a in [false, true] {
    for b in [false, true] {
      assert_true(
        g.cases.any(c => {
          c.expected is None && has(c.args, "a") == a && has(c.args, "b") == b
        }),
      )
    }
  }
  let arrays = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "a": {
          "type": "array",
          "items": { "type": "integer", "minimum": 0, "maximum": 100 },
          "minItems": 3,
          "maxItems": 3,
        },
      },
      "required": ["a"],
      "additionalProperties": false,
    },
  })
  assert_true(
    generate(arrays, 13, 100).any(c => {
      c.expected is None &&
      arr(field(c.args, "a"))[0] != arr(field(c.args, "a"))[1]
    }),
  )
}

///|
test "D04 numeric endpoints and IEEE neighbours" {
  for n in [-1.0, 0.0, 1.0, 9007199254740990.0] {
    assert_true(next_float(n, true) > n)
    assert_true(next_float(n, false) < n)
  }
  let s = compile_schema({ "type": "number", "minimum": -1.0, "maximum": 1.0 })
  assert_true(validate_ir(s, Json::number(-1.0)) is None)
  assert_true(validate_ir(s, Json::number(1.0)) is None)
  assert_true(validate_ir(s, Json::number(next_float(-1.0, false))) is Some(_))
  assert_true(validate_ir(s, Json::number(next_float(1.0, true))) is Some(_))
}

///|
fn string_fixture() -> Spec raise ProbeError {
  load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "text": { "type": "string", "maxLength": 64 } },
      "required": ["text"],
      "additionalProperties": false,
    },
    "output_schema": {
      "type": "object",
      "properties": { "ok": { "type": "boolean" } },
      "required": ["ok"],
    },
  })
}

///|
test "D05 ddmin keeps interior Unicode trigger" {
  let spec = string_fixture()
  let adapter : Adapter = {
    family: "echo",
    version: "interior",
    invoke: x => {
      Ok(
        if text(field(x, "text")).contains("😀BUG") {
          Json::object(Map([]))
        } else {
          { "ok": true }
        },
      )
    },
  }
  let c : Case = {
    index: 0,
    args: { "text": "prefix😀BUGsuffix" },
    category: "valid",
    expected: None,
  }
  let r = shrink_adapter(spec, c, adapter, budget=1000)
  @debug.assert_eq(text(field(r.args, "text")), "😀BUG")
  assert_true(r.trace.length() > 0)
  for step in r.trace {
    assert_true(
      field(step, "signature") ==
      failure_json(run_adapter(spec, c, adapter).failure.unwrap()),
    )
  }
  assert_true(r.attempts <= 1000)
}

///|
test "D06 array intervals and combined fields retain signatures" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "a": { "type": "array", "items": { "type": "integer" }, "maxItems": 16 },
      },
      "required": ["a"],
    },
    "output_schema": {
      "type": "object",
      "properties": { "ok": { "type": "boolean" } },
      "required": ["ok"],
    },
  })
  let adapter : Adapter = {
    family: "echo",
    version: "interval",
    invoke: x => {
      let a = arr(field(x, "a"))
      let mut trigger = false
      for i = 0; i + 1 < a.length(); i = i + 1 {
        if a[i] == Json::number(2.0) && a[i + 1] == Json::number(7.0) {
          trigger = true
        }
      }
      Ok(if trigger { {} } else { { "ok": true } })
    },
  }
  let c : Case = {
    index: 0,
    args: { "a": [9, 9, 2, 7, 8, 8] },
    category: "valid",
    expected: None,
  }
  @debug.assert_eq(
    canonical(field(shrink_adapter(spec, c, adapter, budget=1000).args, "a")),
    "[2,7]",
  )
  let pair = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "a": { "type": "boolean" },
        "b": { "type": "boolean" },
        "z": { "type": "string" },
      },
    },
    "output_schema": {
      "type": "object",
      "properties": { "ok": { "type": "boolean" } },
      "required": ["ok"],
    },
  })
  let both : Adapter = {
    family: "echo",
    version: "pair",
    invoke: x => {
      Ok(
        if field(x, "a") == Json::boolean(true) &&
          field(x, "b") == Json::boolean(true) {
          {}
        } else {
          { "ok": true }
        },
      )
    },
  }
  let c : Case = {
    index: 0,
    args: { "a": true, "b": true, "z": "remove" },
    category: "valid",
    expected: None,
  }
  @debug.assert_eq(
    canonical(shrink_adapter(pair, c, both).args),
    "{\"a\":true,\"b\":true}",
  )
}

///|
test "D07 equal-byte numeric simplification and cache accounting" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 0, "maximum": 10 } },
      "required": ["n"],
    },
    "output_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 5 } },
      "required": ["n"],
    },
  })
  let c : Case = {
    index: 0,
    args: { "n": 4 },
    category: "valid",
    expected: None,
  }
  @debug.assert_eq(
    canonical(shrink_adapter(spec, c, local_adapter("echo", "fixed")).args),
    "{\"n\":0}",
  )
  let constrained = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 3, "maximum": 10 } },
      "required": ["n"],
    },
    "output_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 5 } },
      "required": ["n"],
    },
  })
  let r = shrink_adapter(
    constrained,
    c,
    local_adapter("echo", "fixed"),
    budget=1000,
  )
  @debug.assert_eq(num(field(r.args, "n")), 3.0)
  assert_true(r.cache_hits > 0)
  assert_true(r.adapter_calls < r.attempts)
  let stopped = shrink_adapter(
    spec,
    c,
    local_adapter("echo", "fixed"),
    budget=1,
  )
  @debug.assert_eq(stopped.attempts, 1)
  @debug.assert_eq(stopped.reason, "budget_exhausted")
}

///|
test "D08 grouping retains distinct original inputs and reports cost" {
  let report = test_report(demo(), 20261123, 32, "buggy")
  @debug.assert_eq(num(field(report, "format_version")), 2.0)
  @debug.assert_eq(num(field(report, "failure_signature_count")), 1.0)
  assert_true(num(field(report, "failed")) > 1.0)
  @debug.assert_eq(
    arr(field(report, "corpus")).length(),
    num(field(report, "failed")).to_int(),
  )
  let stats = field(report, "execution")
  assert_true(
    num(field(stats, "total_adapter_calls")) >
    num(field(stats, "main_adapter_calls")),
  )
  for e in arr(field(report, "corpus")) {
    assert_true(
      nodes(field(e, "reduced_input")) <= nodes(field(e, "original_input")),
    )
  }
}
