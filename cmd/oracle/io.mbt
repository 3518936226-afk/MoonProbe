///|
#borrow(path)
extern "C" fn read_native(path : Bytes) -> Bytes = "mp_read_file"

///|
suberror LocalIO {
  IOError(String)
}

///|
fn read_text(path : String) -> String raise {
  if path.contains_char('\u0000') {
    raise @engine.Invalid("NUL in path")
  }
  let bytes = read_native(@utf8.encode(path + "\u0000"))
  if bytes[0] == 2 {
    raise @engine.Invalid("file exceeds 1 MiB")
  }
  if bytes[0] != 0 {
    raise IOError("cannot read vectors")
  }
  @utf8.decode(bytes[1:])
}
