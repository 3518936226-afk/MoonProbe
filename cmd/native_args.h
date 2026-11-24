/* OS-only argument bridge. MinGW's pinned MoonBit env fallback widens ANSI
   bytes; read Windows UTF-16 directly without changing the official runtime. */
#ifndef MOONPROBE_NATIVE_ARGS_H
#define MOONPROBE_NATIVE_ARGS_H
#include "moonbit.h"
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>
#include <string.h>

MOONBIT_EXPORT moonbit_string_t *mp_cli_args(void) {
  int count = 0;
  wchar_t **values = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!values) return (moonbit_string_t *)moonbit_empty_ref_array;
  moonbit_string_t *result = (moonbit_string_t *)moonbit_make_ref_array_raw(count);
  for (int i = 0; i < count; ++i) {
    size_t length = wcslen(values[i]);
    result[i] = moonbit_make_string_raw((int32_t)length);
    memcpy(result[i], values[i], length * sizeof(wchar_t));
  }
  LocalFree(values);
  return result;
}
#endif
