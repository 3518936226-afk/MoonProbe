# Contributing

Use a fresh D-drive checkout, PowerShell 7, MinGW GCC and the versions in toolchain.lock.json. Follow README.md for setup. Configure MOONPROBE_GCC_BIN when GCC is outside the default local installation.

Report reproducible issues using the supplied template. Include the source commit, ToolSpec (remove private data), exact command, expected/actual behavior, exit code and smallest relevant report. Do not upload credentials, access tokens or customer data. State whether the tool is a built-in fixture, this repository's real stdlib integration, or your own adapter.

Changes should explain the concrete problem and resulting behavior, name any schema/compatibility change and include relevant verification. Run scripts/harness.ps1 for normal code changes; scripts/verify-process.py for process transport changes; scripts/verify-all.ps1 for a full release check. Compiler failures and timeouts do not count as killed mutants. Preserve unmodified upstream fixtures and their licenses.

Commits attributed to Codex document AI-authored work. Contributors should disclose material AI assistance and review the resulting code. Only a participant can sign off their own understanding and complete the competition's human/account steps.
