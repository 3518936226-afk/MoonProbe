///|
fn main {
  let argv = @env.args()
  if argv.length() != 2 {
    eprintln("Internal oracle driver: vectors.json")
    @env.exit(2)
  }
  let results = try {
    let input = @json.parse(
      read_text(argv[1]),
      reject_duplicate_keys=true,
      max_nesting_depth=32,
    )
    let rows = @engine.arr(input)
    let out : Array[@json.Json] = []
    for row in rows {
      let item : @json.Json = try {
        let schema = @engine.compile_schema(@engine.field(row, "schema"))
        let error = @engine.validate_ir(schema, @engine.field(row, "data"))
        {
          "valid": error is None,
          "error": @engine.expected_json(error),
          "schema_error": @json.Json::null(),
        }
      } catch {
        @engine.Invalid(s) => { "schema_error": s }
      }
      out.push(item)
    }
    out
  } catch {
    e => {
      eprintln(e.to_string())
      @env.exit(2)
    }
  }
  println(@engine.canonical(@json.Json::array(results)))
}
