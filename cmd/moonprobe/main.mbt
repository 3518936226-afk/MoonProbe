///|
using @json {type Json}

///|
struct Config {
  command : String
  spec_path : String
  corpus_path : String
  version : String
  seed : Int32
  cases : Int32
  out : String
  workload : String
  repeat : Int32
  shrink_budget : Int32
  process_config : String
}

///|
fn bad(s : String) -> Unit raise @engine.ProbeError {
  raise @engine.Invalid(s)
}

///|
fn integer(s : String) -> Int32 raise @engine.ProbeError {
  if s == "" {
    bad("empty integer")
  }
  let mut n = 0
  for c in s {
    if !c.is_ascii_digit() || n > 214748364 || (n == 214748364 && c > '7') {
      bad("integer must be 0..2147483647")
    }
    n = n * 10 + c.to_int() - 48
  }
  n
}

///|
fn parse(argv : Array[String]) -> Config raise @engine.ProbeError {
  if argv.length() < 2 {
    bad("usage: moonprobe inspect|test|replay|bench <toolspec> [options]")
  }
  let command = argv[1]
  if !["inspect", "test", "replay", "bench"].contains(command) {
    bad("unknown command: " + command)
  }
  if argv.length() < 3 {
    bad("ToolSpec path required")
  }
  let spec_path = argv[2]
  let mut corpus_path = ""
  let mut version = "fixed"
  let mut seed = 20261123
  let mut cases = 32
  let mut out = ""
  let mut workload = "generate"
  let mut repeat = 20
  let mut shrink_budget = 100
  let mut process_config = ""
  let mut i = 3
  if command == "replay" {
    if i >= argv.length() {
      bad("corpus directory required")
    }
    corpus_path = argv[i]
    i += 1
  }
  let seen : Map[String, Bool] = Map([])
  while i < argv.length() {
    let k = argv[i]
    if seen.contains(k) {
      bad("duplicate option: " + k)
    }
    seen[k] = true
    if i + 1 >= argv.length() {
      bad("option value required: " + k)
    }
    let v = argv[i + 1]
    match k {
      "--process" => {
        if command != "test" && command != "replay" {
          bad("--process only supported by test and replay")
        }
        if v == "" {
          bad("process config path required")
        }
        process_config = v
      }
      "--mock" => {
        if command == "inspect" || command == "bench" {
          bad("--mock only supported by test and replay")
        }
        if !["buggy", "fixed"].contains(v) {
          bad("--mock must be buggy or fixed")
        }
        version = v
      }
      "--seed" => {
        if command != "test" {
          bad("--seed only supported by test")
        }
        seed = integer(v)
      }
      "--cases" => {
        if command != "test" {
          bad("--cases only supported by test")
        }
        cases = integer(v)
        if cases < 1 || cases > 200 {
          bad("--cases must be 1..200")
        }
      }
      "--shrink-budget" => {
        if command != "test" {
          bad("--shrink-budget only supported by test")
        }
        shrink_budget = integer(v)
        if shrink_budget < 1 || shrink_budget > 1000 {
          bad("--shrink-budget must be 1..1000")
        }
      }
      "--out" => {
        if command != "test" {
          bad("--out only supported by test")
        }
        if v == "" {
          bad("empty output directory")
        }
        out = v
      }
      "--workload" => {
        if command != "bench" ||
          !["generate", "execute", "shrink", "compare"].contains(v) {
          bad("bench workload must be generate, execute or shrink")
        }
        workload = v
      }
      "--repeat" => {
        if command != "bench" {
          bad("--repeat only supported by bench")
        }
        repeat = integer(v)
        if repeat < 1 || repeat > 1000 {
          bad("--repeat must be 1..1000")
        }
      }
      _ => bad("unknown option: " + k)
    }
    i += 2
  }
  if command == "test" && out == "" {
    bad("test requires --out <directory>")
  }
  if process_config != "" && seen.contains("--mock") {
    bad("--process and --mock are mutually exclusive")
  }
  {
    command,
    spec_path,
    corpus_path,
    version,
    seed,
    cases,
    out,
    workload,
    repeat,
    shrink_budget,
    process_config,
  }
}

///|
fn read_json(path : String) -> Json raise {
  let raw = read_text(path)
  @json.parse(
    raw,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    e => {
      bad("invalid JSON: " + path + ": " + e.to_string())
      Json::null()
    }
  }
}

///|
fn benchmark(
  spec : @engine.Spec,
  workload : String,
  repeat : Int32,
) -> Json raise @engine.ProbeError {
  if workload == "compare" {
    return compare_algorithms(spec, repeat)
  }
  let cases = @engine.generate(spec, 20261123, 200)
  let failing = cases
    .filter(c => @engine.run_case(spec, c, "buggy").failure is Some(_))
    .get(0)
  if workload == "shrink" && failing is None {
    bad("shrink benchmark needs a reproducible buggy case")
  }
  let mut checksum = 0
  let mut attempts = 0
  let mut termination = "not_applicable"
  let raw : Array[Double] = []
  // Warm-up and measurement share one process. Timings exclude IO and startup.
  for sample = 0; sample < 35; sample = sample + 1 {
    let clock = @bench.monotonic_clock_start()
    for iteration = 0; iteration < repeat; iteration = iteration + 1 {
      match workload {
        "generate" =>
          for c in @engine.generate(spec, 20261123, 200) {
            if @engine.validate(spec.input, c.args) != c.expected {
              bad("benchmark generator expectation mismatch")
            }
            checksum += @engine.byte_size(c.args)
          }
        "execute" =>
          for c in cases {
            let o = @engine.run_case(spec, c, "fixed")
            if o.failure is Some(_) {
              bad("benchmark fixed case failed")
            }
            if o.called {
              checksum += 1
            }
          }
        _ =>
          if failing is Some(c) {
            let reduced = @engine.shrink(spec, c, "buggy")
            checksum += @engine.byte_size(reduced.args)
            attempts = reduced.attempts
            termination = reduced.reason
          }
      }
    }
    let elapsed = @bench.monotonic_clock_end(clock) *
      1000.0 /
      repeat.to_double()
    if sample >= 5 {
      raw.push(elapsed)
    }
  }
  let sorted = raw.copy()
  sorted.sort()
  {
    "workload": workload,
    "repeat": repeat,
    "warmup": 5,
    "samples": 30,
    "raw_ns": raw,
    "median_ns": (sorted[14] + sorted[15]) / 2.0,
    "p95_ns": sorted[28],
    "clock": "monotonic",
    "seed": 20261123,
    "case_count": 200,
    "checksum": checksum,
    "shrink_attempts": attempts,
    "shrink_termination": termination,
  }
}

///|
fn execute(c : Config) -> Int32 raise {
  let spec = @engine.load_spec(read_json(c.spec_path))
  let adapter = if c.process_config != "" {
    process_adapter(spec, read_json(c.process_config))
  } else {
    if (c.command == "test" || c.command == "replay") &&
      !["echo", "extract_deadline"].contains(spec.adapter) {
      bad("adapter family requires explicit --process configuration")
    }
    @engine.local_adapter(spec.adapter, c.version)
  }
  match c.command {
    "inspect" => {
      println(
        @engine.canonical({
          "engine_version": "0.2.1",
          "mode": "contract_inspection",
          "name": spec.name,
          "adapter_family": spec.adapter,
          "schema_fingerprint": spec.fingerprint,
          "input_schema": spec.input,
          "output_schema": spec.output.unwrap_or(Json::null()),
          "limits": {
            "schema_depth": 8,
            "cases": 200,
            "generation_attempts": 2000,
            "shrink_attempts": 100,
            "max_shrink_attempts": 1000,
            "string_codepoints": 1024,
            "array_items": 64,
            "file_bytes": 1048576,
          },
        }),
      )
      0
    }
    "test" => {
      // Reject an occupied destination before invoking an external tool.
      let report_path = c.out + "/report.json"
      let corpus_path = c.out + "/corpus/entries.json"
      if exists(report_path) || exists(corpus_path) {
        bad(
          "output report or corpus already exists; choose a new --out directory",
        )
      }
      let report = @engine.test_adapter_report(
        spec,
        c.seed,
        c.cases,
        adapter,
        budget=c.shrink_budget,
      )
      let corpus_text = @engine.canonical({
        "format_version": 2,
        "entries": @engine.field(report, "corpus"),
      })
      let report_text = @engine.canonical(report)
      if @utf8.encode(corpus_text).length() > 1048576 ||
        @utf8.encode(report_text).length() > 1048576 {
        bad("ARTIFACT_BUDGET exceeds 1 MiB; use fewer cases or smaller schema")
      }
      make_dirs(c.out)
      if exists(report_path) {
        bad("output report already exists; choose a new --out directory")
      }
      make_dirs(c.out + "/corpus")
      if exists(corpus_path) {
        bad("output corpus already exists; choose a new --out directory")
      }
      write_text(corpus_path, corpus_text)
      write_text(report_path, report_text)
      println(
        @engine.canonical({
          "report": report_path,
          "corpus": c.out + "/corpus",
          "passed": @engine.field(report, "passed"),
          "failed": @engine.field(report, "failed"),
          "adapter_calls": @engine.field(report, "adapter_calls"),
        }),
      )
      if @engine.num(@engine.field(report, "failed")) > 0.0 {
        1
      } else {
        0
      }
    }
    "replay" => {
      let corpus = read_json(c.corpus_path + "/entries.json")
      if @engine.field(corpus, "format_version") != Json::number(1.0) &&
        @engine.field(corpus, "format_version") != Json::number(2.0) {
        bad("corpus envelope format_version must be 1 or 2")
      }
      guard @engine.field(corpus, "entries") is Array(entries) else {
        bad("corpus entries must be an array")
        return 2
      }
      let report = @engine.replay_adapter_report(spec, entries, adapter)
      println(@engine.canonical(report))
      if @engine.num(@engine.field(report, "failed")) > 0.0 {
        1
      } else {
        0
      }
    }
    _ => {
      println(@engine.canonical(benchmark(spec, c.workload, c.repeat)))
      0
    }
  }
}

///|
fn main {
  let argv = @env.args()
  if argv.length() == 2 && argv[1] == "--version" {
    println("MoonProbe 0.2.1")
    return
  }
  if argv.length() == 2 && argv[1] == "--help" {
    println(
      "MoonProbe 0.2.1\ninspect <toolspec>\ntest <toolspec> [--mock buggy|fixed | --process CONFIG] --seed N --cases 1..200 --shrink-budget 1..1000 --out DIR\nreplay <toolspec> <corpus-directory> [--mock buggy|fixed | --process CONFIG]\nbench <toolspec> --workload generate|execute|shrink|compare --repeat 1..1000",
    )
    return
  }
  let code = execute(parse(argv)) catch {
    @engine.Invalid(s) => {
      eprintln("CONFIG: " + s)
      2
    }
    e => {
      eprintln("ENVIRONMENT: " + e.to_string())
      3
    }
  }
  @env.exit(code)
}
