///|
#borrow(exe, argv, cwd, input)
extern "C" fn process_native(
  exe : Bytes,
  argv : Bytes,
  cwd : Bytes,
  input : Bytes,
  timeout : Int32,
) -> Bytes = "mp_process"

///|
fn process_adapter(spec : @engine.Spec, cfg : Json) -> @engine.Adapter raise {
  guard cfg is Object(m) else {
    raise @engine.Invalid("process configuration must be an object")
  }
  for k in m.keys() {
    if !["family", "version", "executable", "args", "cwd", "timeout_ms"].contains(
        k,
      ) {
      bad("unknown process configuration field: " + k)
    }
  }
  let family = @engine.text(@engine.field(cfg, "family"))
  let version = @engine.text(@engine.field(cfg, "version"))
  let exe = @engine.text(@engine.field(cfg, "executable"))
  let cwd = @engine.text(@engine.field(cfg, "cwd"))
  if family != spec.adapter || version == "" {
    bad("process family must match ToolSpec and version must be nonempty")
  }
  // Explicit local executable; no shell, PATH search, or ToolSpec-embedded command.
  if exe.length() < 4 || exe[1] != ':' || (exe[2] != '/' && exe[2] != '\\') {
    bad("process executable must be an absolute local path")
  }
  if !(cwd.has_prefix("D:/") ||
    cwd.has_prefix("D:\\") ||
    cwd.has_prefix("d:/") ||
    cwd.has_prefix("d:\\")) {
    bad("process cwd and temporary transport files must be on D drive")
  }
  let exe_bytes = os_path(exe)
  let cwd_bytes = os_path(cwd)
  guard @engine.field(cfg, "args") is Array(args) else {
    raise @engine.Invalid("process args must be an array of strings")
  }
  let packed : Array[String] = []
  if args.length() > 32 {
    bad("process args exceeds 32")
  }
  for arg in args {
    guard arg is String(s) else {
      raise @engine.Invalid("process args must be strings")
    }
    if s.contains_char('\u0000') {
      bad("NUL in process argument")
    }
    packed.push(s)
  }
  let argv_bytes = @utf8.encode(packed.map(s => s + "\u0000").join(""))
  let t = @engine.num(@engine.field(cfg, "timeout_ms"))
  if t < 10.0 || t > 5000.0 || t.floor() != t {
    bad("timeout_ms must be 10..5000")
  }
  {
    family,
    version,
    invoke: input => {
      let raw = @utf8.encode(@engine.canonical(input) + "\n")
      if raw.length() > 1048576 {
        return Err("PROCESS_INPUT_LIMIT")
      }
      let response = process_native(
        exe_bytes,
        argv_bytes,
        cwd_bytes,
        raw,
        t.to_int(),
      )
      if response[0] != 0 {
        return Err(
          match response[0] {
            2 => "PROCESS_TIMEOUT"
            3 => "PROCESS_OUTPUT_LIMIT"
            4 => "PROCESS_EXIT"
            _ => "PROCESS_IO"
          },
        )
      }
      let text = @utf8.decode(response[1:]) catch {
        _ => return Err("PROCESS_UTF8")
      }
      let output = @json.parse(
        text,
        max_nesting_depth=32,
        reject_duplicate_keys=true,
        preserve_number_repr=true,
      ) catch {
        _ => return Err("PROCESS_JSON")
      }
      Ok(output)
    },
  }
}
