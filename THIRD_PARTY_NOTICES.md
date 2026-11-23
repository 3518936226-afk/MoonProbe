# Licenses and references

MoonProbe source: Apache License 2.0, see LICENSE. New implementation authored with Codex assistance. No copied third-party Schema validator or property-testing library is included.

MoonBit standard library and the four runtime C source files used during building: Copyright International Digital Economy Academy, Apache-2.0 as stated in their headers. These runtime files remain in the locally downloaded toolchain; their source text has not been copied into this repository. Source: https://github.com/moonbitlang/core and https://cli.moonbitlang.com/.

MoonBit compiler and supporting toolchain binaries are official downloads used as build tools. The source-only delivery does not redistribute the compiler. Consult official toolchain terms before redistributing the offline build-tool archives. GCC is an external prerequisite, not part of the source package.

Native FFI ownership annotations follow https://docs.moonbitlang.com/en/stable/language/ffi.html. CLI separation follows https://docs.moonbitlang.com/en/stable/tutorial/cli-quickstart.html. The SHA-256 implementation follows FIPS PUB 180-4; JSON Pointer escaping follows RFC 6901. The code was written for this project and validated with known-answer tests.

Competition reference: https://moonbitlang.github.io/Hackathon2026/. The six visible criteria are recorded in docs/acceptance.md; this project does not assert an official score or award likelihood.

## v0.2 verification dependencies

fixtures/upstream/schema-suite retains original validation fixtures from json-schema-org/JSON-Schema-Test-Suite commit e2a68a15cd490750fd6b95e604e4054d7d978d1f. Copyright Julian Berman; MIT license is included in that directory. No fixture schema, instance or expected verdict is rewritten to claim upstream conformance.

Independent development oracle: python-jsonschema/jsonschema 4.26.0 (MIT), with version/hash-pinned transitive dependencies in requirements-oracle.txt. They are installed in work/oracle-deps and are not linked into the CLI. Their own license files remain with their installed distributions. Official reference: https://python-jsonschema.readthedocs.io/en/stable/validate/.

The chunk-reduction design references Zeller and Hildebrandt, Simplifying and Isolating Failure-Inducing Input (2002). This is an original bounded implementation; no claim of global minimality is made.
