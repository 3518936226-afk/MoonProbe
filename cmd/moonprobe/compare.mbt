///|
fn measure(label : String, repeat : Int32, work : () -> Int32) -> Json {
  let raw : Array[Double] = []
  let mut checksum = 0
  for i = 0; i < 35; i = i + 1 {
    let clock = @bench.monotonic_clock_start()
    for j = 0; j < repeat; j = j + 1 {
      checksum += work()
    }
    let elapsed = @bench.monotonic_clock_end(clock) *
      1000.0 /
      repeat.to_double()
    if i >= 5 {
      raw.push(elapsed)
    }
  }
  let sorted = raw.copy()
  sorted.sort()
  {
    "label": label,
    "repeat": repeat,
    "warmup": 5,
    "samples": 30,
    "raw_ns": raw,
    "median_ns": (sorted[14] + sorted[15]) / 2.0,
    "p95_ns": sorted[28],
    "checksum": checksum,
  }
}

///|
fn compare_algorithms(
  spec : @engine.Spec,
  repeat : Int32,
) -> Json raise @engine.ProbeError {
  let old = @engine.generate_legacy(spec, 20261123, 200)
  let fresh = @engine.generate_result(spec, 20261123, 200)
  let unique : Map[String, Bool] = Map([])
  for c in old {
    unique[@engine.canonical(c.args)] = true
  }
  let timings : Array[Json] = []
  timings.push(
    measure("generate_legacy", repeat, () => {
      let cases = @engine.generate_legacy(spec, 20261123, 200) catch {
        @engine.Invalid(s) => abort(s)
      }
      let mut bytes = 0
      for c in cases {
        if @engine.validate_ir(spec.input_ir, c.args) != c.expected {
          abort("legacy expectation mismatch")
        }
        bytes += @engine.byte_size(c.args)
      }
      bytes
    }),
  )
  timings.push(
    measure("generate_v2", repeat, () => {
      let g = @engine.generate_result(spec, 20261123, 200) catch {
        @engine.Invalid(s) => abort(s)
      }
      let mut bytes = 0
      for c in g.cases {
        if @engine.validate_ir(spec.input_ir, c.args) != c.expected {
          abort("v2 expectation mismatch")
        }
        bytes += @engine.byte_size(c.args)
      }
      bytes
    }),
  )
  let text_spec = @engine.load_spec({
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
      "properties": { "flag": { "type": "boolean" } },
      "required": ["flag"],
    },
  })
  let text_case : @engine.Case = {
    index: 0,
    args: { "text": "prefix-prefix-BUG-suffix-suffix" },
    category: "valid",
    expected: None,
  }
  let text_adapter : @engine.Adapter = {
    family: "echo",
    version: "synthetic-middle",
    invoke: args => {
      Ok(
        if @engine.text(@engine.field(args, "text")).contains("BUG") {
          {}
        } else {
          { "flag": true }
        },
      )
    },
  }
  let number_spec = @engine.load_spec({
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
  let number_case : @engine.Case = {
    index: 0,
    args: { "n": 4 },
    category: "valid",
    expected: None,
  }
  let array_spec = @engine.load_spec({
    "name": "echo",
    "adapter_id": "echo",
    "input_schema": {
      "type": "object",
      "properties": {
        "items": {
          "type": "array",
          "items": { "type": "integer" },
          "maxItems": 64,
        },
      },
      "required": ["items"],
    },
    "output_schema": {
      "type": "object",
      "properties": { "ok": { "type": "boolean" } },
      "required": ["ok"],
    },
  }) catch {
    @engine.Invalid(s) => abort(s)
  }
  let data = Array::makei(64, i => {
    @json.Json::number(if i == 30 { 2.0 } else if i == 31 { 7.0 } else { 9.0 })
  })
  let array_case : @engine.Case = {
    index: 0,
    args: { "items": data },
    category: "valid",
    expected: None,
  }
  let array_adapter : @engine.Adapter = {
    family: "echo",
    version: "fixture",
    invoke: args => {
      let a = @engine.arr(@engine.field(args, "items"))
      let mut bad = false
      for i = 0; i + 1 < a.length(); i = i + 1 {
        if a[i] == @json.Json::number(2.0) &&
          a[i + 1] == @json.Json::number(7.0) {
          bad = true
        }
      }
      Ok(if bad { {} } else { { "ok": true } })
    },
  }
  let rows : Array[Json] = []
  for
    (name, tool, c, adapter) in [
      ("middle_substring", text_spec, text_case, text_adapter),
      (
        "equal_bytes_number",
        number_spec,
        number_case,
        @engine.local_adapter("echo", "fixed"),
      ),
      ("array_interval", array_spec, array_case, array_adapter),
    ] {
    let mut old_calls = 0
    let counted : @engine.Adapter = {
      family: adapter.family,
      version: adapter.version,
      invoke: args => {
        old_calls += 1
        (adapter.invoke)(args)
      },
    }
    let baseline = @engine.shrink_legacy_adapter(tool, c, counted, budget=100)
    let new = @engine.shrink_adapter(tool, c, adapter, budget=100)
    rows.push({
      "scenario": name,
      "original_input": c.args,
      "legacy_input": baseline.args,
      "v2_input": new.args,
      "legacy_bytes": @engine.byte_size(baseline.args),
      "v2_bytes": @engine.byte_size(new.args),
      "legacy_attempts": baseline.attempts,
      "v2_attempts": new.attempts,
      "legacy_calls": old_calls,
      "v2_calls": new.adapter_calls,
      "v2_cache_hits": new.cache_hits,
      "budget": 100,
    })
    timings.push(
      measure(name + "_legacy", repeat, () => {
        @engine.byte_size(
          @engine.shrink_legacy_adapter(tool, c, adapter, budget=100).args,
        )
      }),
    )
    timings.push(
      measure(name + "_v2", repeat, () => {
        @engine.byte_size(
          @engine.shrink_adapter(tool, c, adapter, budget=100).args,
        )
      }),
    )
  }
  {
    "engine_version": "0.2.2",
    "clock": "monotonic",
    "seed": 20261123,
    "comparison": "v0.1 reference algorithms on the same v0.2 IR/adapter runtime",
    "generation": {
      "legacy_cases": old.length(),
      "legacy_unique_inputs": unique.length(),
      "v2_cases": fresh.cases.length(),
      "v2_unique_inputs": fresh.cases.length(),
      "v2_coverage": @engine.field(fresh.coverage, "covered"),
      "v2_eligible": @engine.field(fresh.coverage, "eligible"),
    },
    "scenarios": rows,
    "timings": timings,
  }
}
