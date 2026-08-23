/** 解析 diagnose.ps1 红灯区（"=== 报告红灯区 ===" 段内的 "! xxx" 行）。 */
export function parseRedFlags(stdout) {
  const section = stdout.split('=== 报告红灯区 ===')[1] ?? ''
  return section.split('\n').map((l) => l.trim())
    .filter((l) => l.startsWith('! '))
    .map((l) => l.slice(2))
}
