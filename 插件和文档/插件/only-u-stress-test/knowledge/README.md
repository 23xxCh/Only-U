# knowledge 目录说明

- `stress-test-tools.json`：**生效知识库**。只有通过三条准入（能力不可达 + 授权干净 + 机器可读接口逐条实测留档）的条目才允许进这里；空数组 = 无可调度工具 = fail-closed。
- `candidates.stress-test.json`：候选条目（待实测）。收录流程：
  1. 下载工具发布包，实测静默参数 / 报告导出 / 退出码，填 `audit.cliEvidence`；
  2. 把 `verified` 改为 `true`、`schedulable` 改为 `true`；
  3. 工具二进制 + LICENSE 放进 `tools\<id>\`；
  4. 条目从 candidates 移入 `stress-test-tools.json`。

所有收录工具必须 MIT/BSD/Apache-2.0/Unlicense/zlib 等宽松协议（允许商业重分发）。GPL/MPL 等传染性协议一律不收录。
