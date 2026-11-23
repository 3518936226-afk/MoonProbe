///|
fn demo() -> Spec raise ProbeError {
  load_spec({
    "name": "extract_deadline",
    "adapter_id": "extract_deadline",
    "input_schema": {
      "type": "object",
      "properties": {
        "date": {
          "type": "string",
          "enum": ["2024-02-29", "2024-02-28", "2023-02-28"],
        },
        "context": { "type": "string", "maxLength": 64 },
        "options": {
          "type": "object",
          "properties": {
            "tags": {
              "type": "array",
              "items": { "type": "string", "maxLength": 16 },
              "maxItems": 3,
            },
          },
          "additionalProperties": false,
        },
      },
      "required": ["date"],
      "additionalProperties": false,
    },
    "output_schema": {
      "type": "object",
      "properties": {
        "deadline": { "type": "string", "minLength": 10, "maxLength": 10 },
      },
      "required": ["deadline"],
      "additionalProperties": false,
    },
  })
}

///|
fn rejects(s : Json) -> Bool {
  try {
    ignore(
      load_spec({ "name": "fixture", "adapter_id": "echo", "input_schema": s }),
    )
    false
  } catch {
    _ => true
  }
}

///|
test "S01 scalar rules hand-labelled fixtures" {
  let fixtures : Array[(Json, Json, String)] = [
    ({ "type": "string", "minLength": 1 }, "", "MIN_LENGTH"),
    ({ "type": "string", "maxLength": 1 }, "😀", ""),
    ({ "type": "string", "maxLength": 1 }, "😀x", "MAX_LENGTH"),
    ({ "type": "integer" }, 1.5, "TYPE"),
    ({ "type": "integer", "minimum": 2 }, 1, "MINIMUM"),
    ({ "type": "number", "maximum": 2.5 }, 2.5, ""),
    ({ "type": "number", "maximum": 2.5 }, 3, "MAXIMUM"),
    ({ "type": "boolean" }, true, ""),
    ({ "type": "boolean" }, "true", "TYPE"),
    ({ "type": "null" }, null, ""),
    ({ "type": "null" }, false, "TYPE"),
    ({ "type": "string", "enum": ["a"] }, "b", "ENUM"),
  ]
  for (s, v, want) in fixtures {
    let got = match validate(s, v) {
      None => ""
      Some(e) => e.code
    }
    @debug.assert_eq(got, want)
  }
}

///|
test "S02 object array and escaped pointer" {
  let s : Json = {
    "type": "object",
    "properties": {
      "a/b~c": {
        "type": "array",
        "items": { "type": "integer" },
        "minItems": 1,
        "maxItems": 2,
      },
    },
    "required": ["a/b~c"],
    "additionalProperties": false,
  }
  assert_true(validate(s, {}) == Some({ code: "REQUIRED", path: "/a~1b~0c", }))
  assert_true(
    validate(s, { "a/b~c": [1, "x"] }) ==
    Some({ code: "TYPE", path: "/a~1b~0c/1", }),
  )
  assert_true(
    validate(s, { "a/b~c": [] }) ==
    Some({ code: "MIN_ITEMS", path: "/a~1b~0c", }),
  )
  assert_true(
    validate(s, { "a/b~c": [1, 2, 3] }) ==
    Some({ code: "MAX_ITEMS", path: "/a~1b~0c", }),
  )
  assert_true(
    validate(s, { "a/b~c": [1], "z": true }) ==
    Some({ code: "ADDITIONAL_PROPERTIES", path: "/z", }),
  )
  assert_true(validate(s, { "a/b~c": [1, 2] }) is None)
  assert_true(validate({ "type": "object" }, { "extra": null }) is None)
}

///|
test "S03 import rejection matrix" {
  for keyword in ["format", "$ref", "pattern", "oneOf", "anyOf", "allOf"] {
    let m : Map[String, Json] = Map([("type", Json::string("object"))])
    m[keyword] = Json::string("unsupported")
    assert_true(rejects(Json::object(m)))
  }
  for
    s in [
      Json::boolean(true),
      { "type": ["object", "null"] },
      { "type": "object", "required": ["missing"] },
      {
        "type": "object",
        "properties": {
          "x": { "type": "string", "minLength": 2, "maxLength": 1 },
        },
      },
      {
        "type": "object",
        "properties": {
          "x": { "type": "integer", "minimum": 0.2, "maximum": 0.8 },
        },
      },
      {
        "type": "object",
        "properties": { "x": { "type": "string", "enum": [] } },
      },
      {
        "type": "object",
        "properties": { "x": { "type": "integer", "enum": ["wrong"] } },
      },
      { "type": "object", "additionalProperties": {} },
      {
        "type": "object",
        "properties": { "x": { "type": "number", "minimum": 1.0e100 } },
      },
    ] {
    assert_true(rejects(s))
  }
}

///|
test "S04 SHA256 and canonical known answers" {
  @debug.assert_eq(
    sha256(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  @debug.assert_eq(
    sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  @debug.assert_eq(
    canonical({ "z": 1, "a": { "b": true, "a": null } }),
    "{\"a\":{\"a\":null,\"b\":true},\"z\":1}",
  )
}

///|
test "S05 fingerprints preserve properties named description" {
  let a = load_spec({
    "name": "x",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "description": "first",
      "properties": { "description": { "type": "string" } },
    },
  })
  let b = load_spec({
    "name": "x",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "description": "changed",
      "properties": { "description": { "type": "string" } },
    },
  })
  let c = load_spec({
    "name": "x",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "description": { "type": "integer" } },
    },
  })
  @debug.assert_eq(a.fingerprint, b.fingerprint)
  assert_true(a.fingerprint != c.fingerprint)
}

///|
test "G01 deterministic generation and fixed all pass" {
  let spec = demo()
  let first = generate(spec, 20261123, 32)
  let second = generate(spec, 20261123, 32)
  @debug.assert_eq(first.length(), 32)
  let mut invalid = 0
  let mut legal = 0
  let mut leap = false
  for i, c in first {
    @debug.assert_eq(
      canonical(case_json(c, 20261123)),
      canonical(case_json(second[i], 20261123)),
    )
    assert_true(run_case(spec, c, "fixed").failure is None)
    if c.expected is Some(_) {
      invalid += 1
      assert_false(run_case(spec, c, "fixed").called)
    } else {
      legal += 1
      if text(field(c.args, "date")) == "2024-02-29" {
        leap = true
      }
    }
  }
  assert_true(invalid > 0 && legal > 0 && leap)
  @debug.assert_eq(generate(spec, 9, 200).length(), 200)
}

///|
test "G02 generation budget and seed diagnostics" {
  let spec = demo()
  assert_true(
    try {
      ignore(generate(spec, 0, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(generate(spec, 0, 201))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(generate(spec, -1, 32))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "R01 adapter error and absent output contract" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": { "type": "object" },
  })
  let c : Case = { index: 0, args: {}, category: "valid", expected: None, }
  assert_true(run_case(spec, c, "fixed").failure is None)
  assert_true(
    run_case(spec, c, "error").failure ==
    Some({ stage: "ADAPTER", code: "MOCK_ERROR", path: "", }),
  )
}

///|
test "H01 shrinking preserves signature and original inputs" {
  let spec = demo()
  let c : Case = {
    index: 0,
    args: {
      "date": "2024-02-29",
      "context": "irrelevant context",
      "options": { "tags": ["a", "b"] },
    },
    category: "valid",
    expected: None,
  }
  let reduced = shrink(spec, c, "buggy")
  @debug.assert_eq(canonical(reduced.args), "{\"date\":\"2024-02-29\"}")
  assert_true(smaller(reduced.args, c.args))
  assert_true(
    run_case(
      spec,
      { index: 0, args: reduced.args, category: "valid", expected: None, },
      "buggy",
    ).failure ==
    run_case(spec, c, "buggy").failure,
  )
  @debug.assert_eq(obj(c.args).length(), 3)
  @debug.assert_eq(
    shrink(spec, c, "buggy", budget=0).reason,
    "budget_exhausted",
  )
  @debug.assert_eq(
    canonical(shrink(spec, c, "buggy", budget=0).args),
    canonical(c.args),
  )
  @debug.assert_eq(shrink(spec, c, "fixed").reason, "not_failure")
  let small : Case = {
    index: 0,
    args: { "date": "2024-02-29" },
    category: "valid",
    expected: None,
  }
  @debug.assert_eq(
    canonical(shrink(spec, small, "buggy").args),
    canonical(small.args),
  )
}

///|
test "P01 replay buggy fixed and changed failure" {
  let spec = demo()
  let report = test_report(spec, 20261123, 32, "buggy")
  let entries = arr(field(report, "corpus"))
  assert_true(entries.length() > 0)
  @debug.assert_eq(
    num(field(replay_report(spec, entries, "fixed"), "failed")),
    0.0,
  )
  let buggy = replay_report(spec, entries, "buggy")
  @debug.assert_eq(
    text(field(arr(field(buggy, "results"))[0], "status")),
    "reproduced",
  )
  let different = replay_report(spec, entries, "different")
  @debug.assert_eq(
    text(field(arr(field(different, "results"))[0], "status")),
    "different_failure",
  )
  assert_true(
    try {
      ignore(replay_report(spec, [], "fixed"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(replay_report(spec, [{}], "fixed"))
      false
    } catch {
      _ => true
    },
  )
  let changed = obj(entries[0]).copy()
  changed["schema_fingerprint"] = Json::string("mismatch")
  assert_true(
    try {
      ignore(replay_report(spec, [Json::object(changed)], "fixed"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "S06 unequal key lengths use lexical ordering" {
  @debug.assert_eq(
    canonical({ "z": 1, "alphabet": 2 }),
    "{\"alphabet\":2,\"z\":1}",
  )
}

///|
test "S07 nested expansion and depth budgets" {
  let leaf : Json = {
    "type": "array",
    "items": { "type": "string" },
    "maxItems": 64,
  }
  assert_true(
    rejects({
      "type": "object",
      "properties": { "x": { "type": "array", "items": leaf, "maxItems": 64 } },
    }),
  )
  let mut nested : Json = { "type": "object" }
  for i = 0; i < 9; i = i + 1 {
    nested = { "type": "object", "properties": { "x": nested } }
  }
  assert_true(rejects(nested))
}

///|
test "H02 numeric shrink rejects changed failure signatures" {
  let spec = demo()
  let c : Case = {
    index: 0,
    args: { "date": "2024-02-29", "context": "long" },
    category: "valid",
    expected: None,
  }
  let expected = run_case(spec, c, "buggy").failure
  for
    result in [
      shrink(spec, c, "buggy", budget=1),
      shrink(spec, c, "buggy", budget=100),
    ] {
    assert_true(
      run_case(
        spec,
        { index: 0, args: result.args, category: "valid", expected: None, },
        "buggy",
      ).failure ==
      expected,
    )
    assert_true(
      run_case(
        spec,
        { index: 0, args: result.args, category: "valid", expected: None, },
        "different",
      ).failure !=
      expected,
    )
  }
}

///|
test "H03 candidate with a different signature is rejected" {
  let spec = demo()
  let c : Case = {
    index: 0,
    args: { "date": "2024-02-29", "context": "long context" },
    category: "valid",
    expected: None,
  }
  let before = run_case(spec, c, "mixed").failure
  let other : Case = {
    index: 0,
    args: { "date": "2024-02-29" },
    category: "valid",
    expected: None,
  }
  assert_true(run_case(spec, other, "mixed").failure != before)
  let reduced = shrink(spec, c, "mixed")
  assert_true(has(reduced.args, "context"))
  @debug.assert_eq(text(field(reduced.args, "context")), "")
  assert_true(
    run_case(
      spec,
      { index: 0, args: reduced.args, category: "valid", expected: None, },
      "mixed",
    ).failure ==
    before,
  )
}

///|
test "H04 numeric and array shrinking preserve valid input" {
  let spec = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 0, "maximum": 100 } },
      "required": ["n"],
    },
    "output_schema": {
      "type": "object",
      "properties": { "n": { "type": "integer", "minimum": 50 } },
      "required": ["n"],
    },
  })
  let c : Case = {
    index: 0,
    args: { "n": 40 },
    category: "valid",
    expected: None,
  }
  let reduced = shrink(spec, c, "fixed")
  @debug.assert_eq(canonical(reduced.args), "{\"n\":0}")
  let spec2 = load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "a": { "type": "array", "items": { "type": "string" }, "maxItems": 3 },
      },
      "required": ["a"],
    },
    "output_schema": {
      "type": "object",
      "properties": {
        "a": { "type": "array", "items": { "type": "string" }, "minItems": 3 },
      },
      "required": ["a"],
    },
  })
  let c2 : Case = {
    index: 0,
    args: { "a": ["x", "y"] },
    category: "valid",
    expected: None,
  }
  @debug.assert_eq(canonical(shrink(spec2, c2, "fixed").args), "{\"a\":[]}")
}

///|
test "R02 unknown mock version cannot silently act fixed" {
  let spec = demo()
  let c : Case = {
    index: 0,
    args: { "date": "2024-02-29" },
    category: "valid",
    expected: None,
  }
  assert_true(
    run_case(spec, c, "typo").failure ==
    Some({ stage: "ADAPTER", code: "UNREGISTERED_VERSION", path: "", }),
  )
}
