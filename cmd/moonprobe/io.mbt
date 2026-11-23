///|
suberror LocalIO {
  IOError(String)
}

///|
#borrow(path)
extern "C" fn read_native(path : Bytes) -> Bytes = "mp_read_file"

///|
#borrow(path, data)
extern "C" fn write_native(path : Bytes, data : Bytes) -> Int32 = "mp_write_file"

///|
#borrow(path)
extern "C" fn mkdir_native(path : Bytes) -> Int32 = "mp_mkdirs"

///|
#borrow(path)
extern "C" fn exists_native(path : Bytes) -> Int32 = "mp_exists"

///|
fn os_path(s : String) -> Bytes raise @engine.ProbeError {
  if s.has_prefix("//") || s.has_prefix("\\\\") {
    raise @engine.Invalid("network paths are outside local-only execution")
  }
  if s.contains_char('\u0000') {
    raise @engine.Invalid("NUL in filesystem path")
  }
  @utf8.encode(s + "\u0000")
}

///|
fn read_text(path : String) -> String raise {
  let bytes = read_native(os_path(path))
  if bytes[0] == 2 {
    raise @engine.Invalid("JSON file exceeds 1 MiB: " + path)
  }
  if bytes[0] != 0 {
    raise IOError("cannot read file: " + path)
  }
  @utf8.decode(bytes[1:]) catch {
    _ => raise @engine.Invalid("file is not valid UTF-8: " + path)
  }
}

///|
fn write_text(path : String, text : String) -> Unit raise {
  if write_native(os_path(path), @utf8.encode(text)) != 0 {
    raise IOError("cannot exclusively write file: " + path)
  }
}

///|
fn make_dirs(path : String) -> Unit raise {
  if mkdir_native(os_path(path)) != 0 {
    raise IOError("cannot create directory: " + path)
  }
}

///|
fn exists(path : String) -> Bool raise {
  let n = exists_native(os_path(path))
  if n < 0 {
    raise IOError("cannot inspect path: " + path)
  }
  n == 1
}
