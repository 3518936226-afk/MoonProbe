# MoonProbe

MoonProbe 是用 MoonBit 实现的离线工具契约测试 CLI。它从本地 ToolSpec 生成合法、边界和反向输入，捕获工具输出违例，缩减复现输入，再用同一份语料验证修复。

当前版本为 Windows x64 Native 0.1.0。所有示例均为合成数据和显式注入故障。默认不联网、不读取凭据、不执行外部工具。运行不需要 MoonBit；从源码构建需要工具链和 MinGW GCC。

## 直接运行

在本目录打开 PowerShell 7。交付包已包含 work/bin/moonprobe.exe；源码仓库需先构建。

~~~powershell
.\MoonProbe.cmd inspect examples/extract-deadline.json
.\MoonProbe.cmd test examples/extract-deadline.json --mock buggy --seed 20261123 --cases 32 --out work/demo-buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock fixed
~~~

buggy 的 test 和 replay **预期退出 1**；fixed 的 replay 退出 0。test 默认 fixed。输出目录须为新的目录，程序拒绝覆盖已有 report.json 或 corpus/entries.json。重复演示时换一个 --out 路径。

示例的 date 枚举包含 2024-02-29、2024-02-28、2023-02-28。日期只是字符串枚举，不提供真实日期格式校验。buggy 在闰日返回缺少 deadline 的对象；fixed 返回该字段。生成器不包含日期工具专用判断。

## 从源码构建和验收

将源码放到 D 盘、无 shell 特殊字符的目录。安装过程不修改用户 PATH，不调用原始安装脚本；临时文件在本项目 work/tmp 中。

~~~powershell
pwsh -NoProfile -File scripts/install-toolchain.ps1
pwsh -NoProfile -File scripts/build-native.ps1
pwsh -NoProfile -File scripts/harness.ps1
pwsh -NoProfile -File scripts/benchmark.ps1
~~~

工具链已安装时跳过安装步骤。可通过进程级 MOON_HOME 复用已安装的同版本工具链。内容校验锁定在 toolchain.lock.json；如果上游 latest 已变化，安装会拒绝不匹配内容。使用留存的原始压缩包时传 -ArchiveDir，目录包含 moonbit-windows-x86_64.zip 和 core.zip。

本机 GCC 15.2 已验证。官方当前构建器会无条件编译仅支持 MSVC 的异步 Windows 运行库，因此这里的 MinGW 验收入口是 build-native.ps1 和 harness.ps1，不能用直接 moon build/test 代替。脚本使用官方 MoonBit 编译器将核心编译为 C，并链接四个未修改的官方同步运行库源文件。详见 docs/architecture.md。

Harness 在 Native 上执行引擎单元测试并检查 CLI 退出码、固定 seed 的完整报告一致性、非法输入零调用、缩减、双版本回放、损坏语料、Unicode 路径和 IO 异常。基准在同一进程内预热 5 次、采样 30 次，每次固定批量重复 20 次；保存原始数据、中位数及 p95，不包含进程启动和文件 IO。

## 接口和限制

ToolSpec 包含 name、adapter_id、input_schema 和可选 output_schema。内置适配器族仅 extract_deadline 与 echo；不接受任意命令、URL 或插件。

- inspect 解析契约并输出 JSON 摘要。
- test 输出 report.json 和 corpus/entries.json。报告保留输入、预期、阶段、规则、JSON Pointer、调用情况及缩减数据。
- replay 优先复验缩减输入，输出 reproduced、fixed 或 different_failure。契约指纹或语料版本不匹配时拒绝比较。
- bench 为维护者提供 generate、execute、shrink 三项固定工作负载。

退出码：0 满足预期，1 工具行为或契约故障，2 参数、Schema 或语料不兼容，3 本地环境或 IO 错误。缺失输出契约时，只判断调用状态。

支持七种单一显式类型、对象属性与必填、布尔 additionalProperties、同构数组、字符串长度、数值闭区间与标量枚举。其余关键字均拒绝。完整限制见 docs/support-matrix.md。

本版本只做结构与契约验证，不评估工具结果的语义正确性。缩减只保证预算内找到的更小同签名反例，不保证全局最小。

## 证据与参赛状态

本地开发记录为真实 Git 提交，AI 生成的提交署名 Codex，未冒用参赛者身份。公开仓库、远端 CI、报名提交、独立开发者试用和人工复核均须按 evidence/index.json 的状态核对，不能从配置文件推断已完成。

工程化、交付完整度、实际影响与技术贡献的证据分别登记。真实案例与独立试用未完成时如实保留缺口。没有实测手工对照，不宣称节省开发时间。

项目采用 Apache-2.0；依赖及参考来源见 THIRD_PARTY_NOTICES.md。赛事需要公开持续开发记录，发布前须核对官方通知；当前公开页面没有给出确定的报名与验收日期。
