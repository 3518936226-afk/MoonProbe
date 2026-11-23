pub fn run_case(spec : Spec, c : Case, version : String) -> Outcome {
  let input_error = validate(spec.input, c.args)
  match c.expected {
    Some(want) => {
      if input_error == Some(want) { return {failure:None,called:false} }
      return {failure:Some({stage:"INPUT_EXPECTATION",code:"EXPECTED_REJECTION",path:want.path}),called:false}
    }
    None => {
      if input_error is Some(e) { return {failure:Some({stage:"INPUT_SCHEMA",code:e.code,path:e.path}),called:false} }
    }
  }
  if version == "error" { return {failure:Some({stage:"ADAPTER",code:"MOCK_ERROR",path:""}),called:true} }
  let output : Json = match spec.adapter {
    "extract_deadline" => {
      if version == "buggy" && text(field(c.args,"date")) == "2024-02-29" { {} }
      else if version == "different" { {"deadline":false} }
      else { {"deadline":field(c.args,"date")} }
    }
    _ => c.args
  }
  if spec.output is Some(s) {
    if validate(s,output) is Some(e) { return {failure:Some({stage:"OUTPUT_SCHEMA",code:e.code,path:e.path}),called:true} }
  }
  {failure:None,called:true}
}

fn shrink_candidates(v : Json) -> Array[Json] {
  let out : Array[Json] = []
  match v {
    Object(m) => {
      for k in keys(v) { let n=m.copy(); n.remove(k); out.push(Json::object(n)) }
      for k in keys(v) { for x in shrink_candidates(m[k]) { out.push(replace_key(v,k,x)) } }
    }
    Array(a) => {
      out.push(Json::array([]))
      if a.length()>1 { out.push(Json::array(a.iter().take(a.length()/2).collect())) }
      for i=0; i<a.length(); i=i+1 {
        let n=a.copy(); ignore(n.remove(i)); out.push(Json::array(n))
        for x in shrink_candidates(a[i]) { let n=a.copy(); n[i]=x; out.push(Json::array(n)) }
      }
    }
    String(s) => {
      let chars=s.iter().collect()
      out.push(Json::string(""))
      if chars.length()>1 { out.push(Json::string(String::from_array(chars.iter().take(chars.length()/2).collect()))) }
    }
    Number(n, ..) => {
      for x in [0.0,n/2.0,(n/2.0).floor(),(n/2.0).ceil()] { out.push(Json::number(x)) }
    }
    True => out.push(Json::boolean(false))
    _ => ()
  }
  out
}
pub fn shrink(spec : Spec, c : Case, version : String, budget? : Int = 100) -> ShrinkResult {
  guard run_case(spec,c,version).failure is Some(signature) else { return {args:c.args,attempts:0,reason:"not_failure"} }
  let mut best=c.args
  let mut attempts=0
  while attempts<budget {
    let mut accepted=false
    for candidate in shrink_candidates(best) {
      if attempts>=budget { break }
      if !smaller(candidate,best) { continue }
      attempts+=1
      // Preserve the original input expectation before testing execution failures.
      if validate(spec.input,candidate)!=c.expected { continue }
      let trial : Case={index:c.index,args:candidate,category:c.category,expected:c.expected}
      if run_case(spec,trial,version).failure == Some(signature) {
        best=candidate; accepted=true; break
      }
    }
    if !accepted { return {args:best,attempts,reason:if attempts>=budget {"budget_exhausted"} else {"local_minimum"}} }
  }
  {args:best,attempts,reason:"budget_exhausted"}
}
