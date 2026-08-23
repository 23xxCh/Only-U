/**
 * 解析预览输出中的保护拦截清单。clean.ps1 有两种输出形态：
 * - 逐条：`blocked (delete-protection): <路径>`（扫描过程中逐目录命中）
 * - 汇总：`blocked by delete-protection:` 段下两空格缩进的行
 */
export function parseBlocked(stdout) {
  const lines = stdout.split('\n').map((l) => l.trim())
  const inline = lines
    .filter((l) => l.startsWith('blocked (delete-protection):'))
    .map((l) => l.slice('blocked (delete-protection):'.length).trim())

  const sectionIdx = lines.indexOf('blocked by delete-protection:')
  const inSection = []
  if (sectionIdx !== -1) {
    const raw = stdout.split('\n').slice(sectionIdx + 1)
    for (const line of raw) {
      if (line.startsWith('  ') && line.trim() !== '') inSection.push(line.trim())
      else if (line.trim() !== '' && !line.startsWith(' ')) break
    }
  }
  return [...new Set([...inline, ...inSection])]
}

/** 从预览输出提取 "preview total about X (allow-listed...)" 中的大小，用作审批理由。 */
export function summarizePreview(stdout) {
  const m = stdout.match(/preview total about (.+?) \(allow-listed/)
  return m ? `约 ${m[1]}` : '未知大小'
}
