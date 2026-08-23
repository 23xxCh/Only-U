/** 退出码 → 含义（逐工具在知识库 exitCodes 表中维护；未收录 = unknown）。 */
export function describeExit(entry, code) {
  if (code === null) return 'no-exit-code'
  return entry.exitCodes?.[String(code)] ?? 'unknown'
}
