# Licenses and references

MoonProbe source: Apache License 2.0, see LICENSE. New implementation authored with Codex assistance. No copied third-party Schema validator or property-testing library is included.

MoonBit standard library and the four runtime C source files used during building: Copyright International Digital Economy Academy, Apache-2.0 as stated in their headers. These runtime files remain in the locally downloaded toolchain; their source text has not been copied into this repository. Source: https://github.com/moonbitlang/core and https://cli.moonbitlang.com/.

MoonBit compiler and supporting toolchain binaries are official downloads used as build tools. The source-only delivery does not redistribute the compiler. Consult official toolchain terms before redistributing the offline build-tool archives. GCC is an external prerequisite, not part of the source package.

Native FFI ownership annotations follow https://docs.moonbitlang.com/en/stable/language/ffi.html. CLI separation follows https://docs.moonbitlang.com/en/stable/tutorial/cli-quickstart.html. The SHA-256 implementation follows FIPS PUB 180-4; JSON Pointer escaping follows RFC 6901. The code was written for this project and validated with known-answer tests.

Competition reference: https://moonbitlang.github.io/Hackathon2026/. The six visible criteria are recorded in docs/acceptance.md; this project does not assert an official score or award likelihood.
