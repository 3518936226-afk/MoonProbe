# MoonProbe

[![Native verification](https://github.com/3518936226-afk/MoonProbe/actions/workflows/native.yml/badge.svg)](https://github.com/3518936226-afk/MoonProbe/actions/workflows/native.yml)

MoonProbe 是以 **MoonBit 为主要实现语言**的离线工具契约测试引擎：编译类型化 Schema IR，生成唯一的合法/边界/反向输入，检查工具输出、缩减同签名反例，再用历史语料验证修复。支持 Windows x64 Native。

v0.2.1 已接入真实 Python 标准库 URL 表单解析器，复现并修复空值保留配置与消费契约不匹配。这个案例不是 Python 上游缺陷，内置 buggy/fixed 示例则是明确标注的合成夹具。

## 下载运行（无需编译）

[下载 v0.2.1 Windows x64 交付包](https://github.com/3518936226-afk/MoonProbe/raw/refs/heads/main/MoonProbe-0.2.1-windows-x64.zip)，解压到 D 盘，在解压后的 MoonProbe-0.2.1 目录打开 PowerShell 7：

~~~powershell
.\MoonProbe.cmd --version
.\MoonProbe.cmd inspect examples/extract-deadline.json
.\MoonProbe.cmd test examples/extract-deadline.json --mock buggy --seed 20261123 --cases 32 --shrink-budget 100 --out work/demo-buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock fixed
~~~

buggy 的 test/replay 预期退出 1，fixed 回放退出 0。输出目录必须尚未存在。CLI 本身无需 Python、网络、账号或凭据；真实进程案例另外需要已有 Python 3.12。ZIP 含程序、源码、完整 Git 历史、逐文件哈希和原始验证记录；其状态说明冻结于发布时。

ZIP SHA-256：1ca5368641c9f744155585335b8980098101fd1789362735d16f43d05cefd7f5。

## 从源码构建

前提：Windows x64、PowerShell 7、Git、MinGW GCC。工具链版本/哈希固定在 [toolchain.lock.json](toolchain.lock.json)。源码检出不会包含预编译程序。

~~~powershell
# 在可写的 D 盘目录中执行；目标目录必须尚未存在。
git clone https://github.com/3518936226-afk/MoonProbe.git D:/VAPP/moonprobe
Set-Location D:/VAPP/moonprobe
# GCC 不在默认位置或 PATH 时，先设置其 bin 目录：
# $env:MOONPROBE_GCC_BIN = 'D:/你的编译器/bin'
pwsh -NoProfile -File scripts/install-toolchain.ps1
pwsh -NoProfile -File scripts/build-native.ps1
pwsh -NoProfile -File scripts/harness.ps1
~~~

已有相同版本 MoonBit 时可设置进程级 MOON_HOME 并跳过安装。安装器使用官方版本地址并核验完整 SHA-256，不修改系统 PATH；可用 -ArchiveDir 指向本地留存的原始压缩包。上游下载存在保留期限，不保证永久可用，也不接受未核验替换。编译器二进制未被本仓库重新分发。

当前固定工具链的官方 Native 构建会额外计划要求 MSVC 的 Windows 异步运行库。本项目使用官方编译器的同步构建计划，并链接四个未修改的官方同步运行库源文件；MinGW 下请使用上述 build-native.ps1/Harness 入口。MoonBit 实现业务逻辑，C 文件仅处理本地 IO 与进程管理。其他 OS/后端尚未验收。

## 真实工具复现

~~~powershell
# 使用已有 Python 3.12 x64 的完整路径；证据目录必须是新的 D 盘目录。
& 'Python的完整路径' -B scripts/verify-process.py --out 'D:/新的进程证据目录'
~~~

32 个生成输入在默认 parse_qs 配置下发现 3 个同签名输出违例；153 字节反例缩到 12 字节的 {"value":""}。开启 keep_blank_values 后，3 条历史反例及新生成的 32 个输入均通过。另检查空值、转义、中文、emoji、NUL 和换行等 7 个往返语义样本。

--process CONFIG 用于 test/replay，配置中显式指定 executable、args、cwd、family、version 和 timeout_ms。它直接调用可信本地程序，采用 JSON stdin/stdout；不是 shell、沙箱或 MCP。详见 [案例、协议和资源限制](docs/real-tool-case.md)。

## 验证与证据

v0.2.1 的已运行本地证据见 [evidence/local-v0.2.1/README.md](evidence/local-v0.2.1/README.md)：66 项验收（29 组 Native 单元测试）、64 项真实工具/传输检查、100 份契约与 10,000 组独立差分（差异 0）、12 个成功编译且被识别的源码变异。另有干净检出复现与原始基准记录。

完整开发验证另需 Python 3.12 x64。开发依赖锁定版本和 wheel 哈希，只安装到项目 work/：

~~~powershell
$env:MOONPROBE_PYTHON = 'Python的完整路径'
pwsh -NoProfile -File scripts/setup-depth.ps1
pwsh -NoProfile -File scripts/verify-all.ps1
~~~

[GitHub Actions](https://github.com/3518936226-afk/MoonProbe/actions/workflows/native.yml) 在独立 Windows runner 上执行同一套 Native、真实进程、差分、变异和基准检查，并上传原始日志。以具体运行的结论为准；配置存在不等于通过。云端 GCC 使用 MSYS2 官方包，日志记录实际版本；本地旧基准不能直接作为跨机器性能比较。

## 能力边界

--cases 是唯一输入数量上限，有限空间或候选预算耗尽时停止。覆盖是声明目标的见证覆盖，不是分支覆盖或完整正确性证明。缩减保持输入预期与失败签名，在预算内寻找更简单反例，不承诺全局最小。签名组数不等于根因数。

支持的 JSON Schema 子集及预算见 [支持矩阵](docs/support-matrix.md)。官方测试夹具按固定提交原样保留，57 个选入用例与排除原因如实记录，不代表完整 JSON Schema 标准认证。未实现业务语义 LLM 判断、MCP 或网络服务。

## 开源与参赛说明

项目采用 [Apache-2.0](LICENSE)。第三方来源与原始 MIT 测试集许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。项目并非移植第三方测试引擎；参考库仅用于开发验证。

源码中的历史提交保留原始时间和 Codex 作者归属，并与最初的 GitHub 上传记录合并。后续使用实际 [Issues](https://github.com/3518936226-afk/MoonProbe/issues)、[PR](https://github.com/3518936226-afk/MoonProbe/pulls) 和提交记录追踪工作，不把自动验证说成人工复核。

[架构](docs/architecture.md) · [v0.2 算法设计](docs/v0.2-design.md) · [AI 辅助与复核记录](docs/ai-review.md) · [参赛要求对应表](docs/acceptance.md) · [参与者理解清单](docs/participant-review.md) · [贡献指南](CONTRIBUTING.md)

人工理解与签字、加入赛事群并使用 GitHub ID 作为昵称、官方时间核对、报名/提交、独立开发者试用及真人录屏仍需参与者完成。当前不承诺赛事资格、分数或奖金。