# Native build scripts
PowerShell 7 is required. Run scripts from a path without shell metacharacters.
All compiler commands are emitted by the pinned MoonBit build planner from this local source tree. No ToolSpec or corpus text is evaluated as a shell command.
The MinGW build entrypoint compiles MoonBit to C with the official compiler and links only runtime.c, env.c, utf.c and backtrace.c, unchanged from the official toolchain. The generated CLI and the official native test driver both use the same synchronous runtime subset.
Direct moon build/test with the pinned release attempts to compile the entire async Windows runtime, which requires MSVC. Use build-native.ps1 and harness.ps1 on this MinGW installation.
