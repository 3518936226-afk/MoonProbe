# MoonProbe

MoonProbe 是以 MoonBit 为主要实现语言的离线工具契约测试引擎。v0.2 从本地 ToolSpec 编译带类型的契约 IR，生成唯一的合法、边界和反向输入，定位输出契约违例，缩减反例，并用历史语料验证修复。

首发 Windows x64 Native。示例与故障均为合成夹具。CLI 无需 Python、网络、凭据或外部工具进程；仅源码构建和开发验证需要额外工具。

## 运行

解压交付包，在本目录打开 PowerShell 7：

~~~powershell
.\MoonProbe.cmd inspect examples/extract-deadline.json
.\MoonProbe.cmd test examples/extract-deadline.json --mock buggy --seed 20261123 --cases 32 --shrink-budget 100 --out work/demo-buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock buggy
.\MoonProbe.cmd replay examples/extract-deadline.json work/demo-buggy/corpus --mock fixed
~~~

buggy 的 test/replay 预期退出 1；fixed 回放退出 0。test 默认 fixed，输出目录须为新目录，拒绝覆盖既有报告和语料。日期字符串使用明确枚举；本项目不提供日期格式语义判断。

v0.2 中 --cases N 是唯一用例数量的上限，不保证补足 N。有限合法空间已穷尽或候选预算耗尽时停止，报告分别记录 space_exhausted、budget_exhausted 或 case_limit。固定边界见证优先，seed 用于剩余预算内的补充探索；较小预算可能完全被确定性边界见证占用。

报告分别列出失败用例数、失败签名组数、覆盖见证、未覆盖原因、主执行/缩减调用、实际校验次数及缓存命中。一个签名组不是一个已证明的根因。格式 v2 保留不同失败输入的语料，兼容读取 v1 语料。

退出码继续为 0 满足预期、1 工具或契约故障、2 参数/契约/语料/资源能力不兼容、3 本地环境或 IO 错误。完整接口见 --help。内部 oracle 驱动用于开发验证，不属于稳定 CLI 接口。

## 从源码构建

在 D 盘、无 shell 特殊字符的目录中使用 PowerShell 7、MinGW GCC 和固定的 MoonBit 工具链。已有同版本工具链可通过进程级 MOON_HOME 复用。

~~~powershell
pwsh -NoProfile -File scripts/install-toolchain.ps1
pwsh -NoProfile -File scripts/build-native.ps1
pwsh -NoProfile -File scripts/harness.ps1
~~~

已有工具链时跳过安装。所有可配置临时文件、依赖和缓存在项目 work/ 中。工具链内容按 toolchain.lock.json 的 SHA-256 校验；上游 latest 内容变化时拒绝替换，可通过 -ArchiveDir 使用留存的同哈希原始压缩包。

本机 MinGW 的验收入口为 build-native.ps1 和 harness.ps1。官方固定版本的 moon build/test 会无条件编译要求 MSVC 的 Windows 异步运行库；这里使用官方编译器计划并链接未修改的四个同步运行库源文件。业务逻辑仍在 MoonBit 中，C 文件仅处理 UTF-8 本地路径和文件 IO。

## 深度验证

独立参考库仅用于开发，锁定 Python 3.12 x64 与带哈希的 jsonschema 4.26.0 依赖。MOONPROBE_PYTHON 指定已有 Python 可执行文件；不新建 C 盘环境。

~~~powershell
$env:MOONPROBE_PYTHON = '已有的 Python 3.12 可执行文件完整路径'
pwsh -NoProfile -File scripts/setup-depth.ps1
pwsh -NoProfile -File scripts/verify-all.ps1
~~~

verify-all 依次运行全量 Native Harness、独立差分、源码变异和基准。独立差分固定 100 份契约、10000 组实例，再检查生产生成器的唯一性与预期。官方 JSON Schema 测试集按固定提交原样留存，只选择声明子集内且适用于 2020-12 的测试；选择和排除记录一并保存，不能解读为完整标准认证。

源码变异在独立 work/ 副本中注入 12 种预定义错误。每个变异必须成功编译并被测试识别；编译错误、超时或不完整结果不会被记成成功杀死。

~~~powershell
.\MoonProbe.cmd bench examples/extract-deadline.json --workload compare --repeat 20
~~~

算法对照使用同机、同工具链、同构建模式；每项预热 5 次、采样 30 次。分别展示唯一输入数、反例质量、实际调用和耗时，不把更深的搜索包装成全面提速。legacy 与 v2 的尝试计数口径不同，比较执行成本时使用实际适配器调用和原始耗时。

## 边界与交付状态

支持的 Schema 子集及资源限制见 docs/support-matrix.md，算法与覆盖口径见 docs/v0.2-design.md。缩减只承诺预算内找到更简单的同签名输入，不保证全局最小。覆盖是声明目标的见证覆盖，不是程序分支覆盖，也不证明业务语义正确。

项目采用 Apache-2.0，第三方原始测试集保留 MIT 许可证。参考校验库及传递依赖只在开发目录安装。依赖来源见 THIRD_PARTY_NOTICES.md。

公开仓库、远端 CI 成功运行、真实用户案例、人工复核、独立开发者试用与现场录屏仍按 evidence/index.json 如实登记。演示 GIF 是真实命令输出生成的动画，不是桌面录屏。未执行赛事报名或提交。
