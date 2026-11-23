///|
pub(all) struct Adapter {
  family : String
  version : String
  invoke : (Json) -> Result[Json, String]
}

///|
pub fn local_adapter(family : String, version : String) -> Adapter {
  {
    family,
    version,
    invoke: args => {
      if !["buggy", "fixed", "error", "different", "mixed"].contains(version) ||
        !["extract_deadline", "echo"].contains(family) {
        return Err("UNREGISTERED_VERSION")
      }
      if version == "error" {
        return Err("MOCK_ERROR")
      }
      if family == "echo" {
        return Ok(args)
      }
      if (version == "buggy" || version == "mixed") &&
        text(field(args, "date")) == "2024-02-29" {
        if version == "mixed" && !has(args, "context") {
          Ok({ "deadline": false })
        } else {
          Ok({})
        }
      } else if version == "different" {
        Ok({ "deadline": false })
      } else {
        Ok({ "deadline": field(args, "date") })
      }
    },
  }
}

///|
pub fn run_adapter(spec : Spec, c : Case, adapter : Adapter) -> Outcome {
  if adapter.family != spec.adapter {
    return {
      failure: Some({ stage: "ADAPTER", code: "FAMILY_MISMATCH", path: "", }),
      called: false,
    }
  }
  let input_error = validate_ir(spec.input_ir, c.args)
  match c.expected {
    Some(want) => {
      if input_error == Some(want) {
        return { failure: None, called: false, }
      }
      return {
        failure: Some({
          stage: "INPUT_EXPECTATION",
          code: "EXPECTED_REJECTION",
          path: want.path,
        }),
        called: false,
      }
    }
    None =>
      if input_error is Some(e) {
        return {
          failure: Some({ stage: "INPUT_SCHEMA", code: e.code, path: e.path, }),
          called: false,
        }
      }
  }
  let output = match (adapter.invoke)(c.args) {
    Ok(value) => value
    Err(code) =>
      return {
        failure: Some({ stage: "ADAPTER", code, path: "", }),
        called: code != "UNREGISTERED_VERSION",
      }
  }
  if spec.output_ir is Some(schema) {
    if validate_ir(schema, output) is Some(e) {
      return {
        failure: Some({ stage: "OUTPUT_SCHEMA", code: e.code, path: e.path, }),
        called: true,
      }
    }
  }
  { failure: None, called: true, }
}

///|
pub fn run_case(spec : Spec, c : Case, version : String) -> Outcome {
  run_adapter(spec, c, local_adapter(spec.adapter, version))
}
