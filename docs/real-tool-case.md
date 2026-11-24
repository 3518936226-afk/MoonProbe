# 真实工具进程接入：URL 表单空值保留

v0.2.1 新增 Windows 本地子进程适配器，核心生成、契约校验、缩减、报告和回放仍由 MoonBit 实现。通过独立 JSON 配置显式选择进程，不从 ToolSpec 执行命令。

## 实际案例及结论

工具为已有 Python 标准库 urllib.parse。tools/url_query.py 仅把 stdin JSON 字段编码为查询串，再调用真实的 parse_qs，输出 value 字段对应的 values 数组。消费方契约明确要求一个解码值，空字符串也必须保留。

默认 parse_qs 不保留空值，这是其文档规定的行为。因此本案例是实际库与消费方要求之间的配置契约不匹配，**不是发现了 Python 上游缺陷，也不是已有第三方产品的故障案例**。脚本没有按输入注入错误，修复仅采用正常的 keep_blank_values 配置选项。

32 个生成用例中，默认配置出现 3 个同签名失败：OUTPUT_SCHEMA / MIN_ITEMS /values。缩减可移除无关 context，将 153 字节输入缩到 12 字节的 {"value":""}。开启 --keep-blank-values 后，同一份 3 条语料全部修复，新生成的 32 个用例全部通过。

生成器在此仅检查输出形状。独立脚本另用空值、转义字符、中文、emoji、NUL 和换行共 7 个值检查往返语义；不能把这些样本推广为完整语义正确性证明。

参考：[Python 3.12 parse_qs 文档](https://docs.python.org/3.12/library/urllib.parse.html#urllib.parse.parse_qs)。keep_blank_values 的实际行为在本机 Python 3.12 上再次执行核验。

## 复现

在 D 盘源码目录中，使用已有 Python 3.12+；CLI 本身不需要 Python，只有本案例工具需要。

~~~powershell
pwsh -NoProfile -File scripts/build-native.ps1
& '已有 Python 的完整路径' -B scripts/verify-process.py --out 'D:/独立的新证据目录'
~~~

脚本生成 stdlib-default.config.json、stdlib-preserve-empty.config.json、原始报告、语料、回放日志、独立语义样本与摘要。重复运行须选择新目录。配置记录实际本机绝对路径；移动交付包后应重新运行脚本生成配置，不直接复用旧机器路径。

~~~powershell
.\MoonProbe.cmd test examples/url-query.json --process '证据目录/stdlib-default.config.json' --cases 32 --out 'D:/新的测试目录'
.\MoonProbe.cmd replay examples/url-query.json 'D:/新的测试目录/corpus' --process '证据目录/stdlib-preserve-empty.config.json'
~~~

默认测试退出 1，保留空值的修复回放退出 0。

## 进程协议与限制

配置必填 family、version、executable、args、cwd、timeout_ms。family 必须匹配 ToolSpec 的 adapter_id；executable 为本地绝对路径，args 为最多 32 个字符串；cwd 必须在 D 盘且已存在；timeout_ms 为 10..5000。--process 与 --mock 互斥，适用于 test/replay。inspect 不执行工具；bench 继续用于内置算法基准。

每次调用启动一个进程；stdin 是一个 UTF-8 JSON 对象，读至 EOF。工具必须退出 0，并在 stdout 返回恰好一个完整 UTF-8 JSON 值。stderr 不作为契约输出。重复键、非法 JSON/UTF-8、非零退出、超时、IO 与超限分别分类。stdio 仅重定向到 cwd 下 delete-on-close 临时文件；输出文件每 10ms 检查，检测到任一流超过 1 MiB 后终止。它是轮询检测限额，不是硬磁盘配额，写入突发可能超过阈值。

CreateProcessW 直接运行可执行文件，不使用 shell 或 PATH 搜索。参数按 Windows CRT 规则引用；仅传入必要 stdio 句柄。Job Object 在超时或完成后终止进程树。临时文件关闭时删除；已有输出报告在调用工具前即拒绝覆盖。错误报告只提供分类，不保存工具 stderr，避免意外把凭据放入交付。

这是可信本地工具的进程管理，不是沙箱；子工具继承运行用户权限和环境，仍可能访问网络、凭据或自行写文件。本案例使用 -I -B 运行纯标准库脚本，无网络、无账户，也不生成 Python 字节码；验证脚本的可配置临时路径均在 D 盘。

传输故障测试位于 fixtures/process_fixture.py，明确属于人工夹具，与上述真实解析器案例分开记录。公开仓库、远端 CI、独立开发者试用、真人录屏及真实用户缺陷仍未完成。
