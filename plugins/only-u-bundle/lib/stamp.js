/** Pure helpers for Only-U TUI stamps. No I/O. */

export const PROTECT = '桌面 / 文档 / 下载 / 聊天记录 不会动'
export const PROTECT_SHORT = '桌面 / 文档 / 下载 / 聊天记录'

export function shouldSkipAuto(env = process.env) {
  return env.ONLY_U_SKIP_AUTO === '1'
}

export function footerLines(previewSize) {
  const amount = previewSize ? `约 ${previewSize}` : '见清理预览'
  return [
    `能清多少：${amount}`,
    '不碰什么：桌面 / 文档 / 下载 / 图片 / 聊天记录',
    '说确认才删：现在没有删除任何文件',
  ]
}

export function reportStamp({ kind, conclusion, suggest, next, close, extra, previewSize, narrow = false }) {
  const lines = [`[${kind}] ${conclusion}`]
  if (narrow) {
    lines.push(`保护：${PROTECT_SHORT}`)
    lines.push(...footerLines(previewSize))
    if (close) lines.push(close)
    return lines.join('\n')
  }
  if (suggest) lines.push(`建议：${suggest}`)
  lines.push(`保护：${PROTECT}`)
  if (next) lines.push(`下一步：${next}`)
  lines.push(...footerLines(previewSize))
  if (close) lines.push(close)
  if (extra) lines.push(extra)
  return lines.join('\n')
}

export function nextStep(state) {
  if (state.hasNet === false && state.boot === 'done') {
    return '没网不能对话。输入 /clean 选确认清理，或用盘根 诊断.cmd'
  }
  if (state.hasNet === false) return '先用盘根 诊断.cmd（不用网）'
  if (!state.hasKey) return '输入 /provider 填 Key，或先用盘根 诊断.cmd'
  if (state.boot === 'failed') return '开机体检失败。用盘根 诊断.cmd，或输入 /diagnose'
  if (state.boot === 'done') return '看完预览后输入「确认」才会删除'
  return '正在自动诊断与清理预览…'
}

export function idleStatus(state, diskLine) {
  if (state.hasNet === false) return '这台电脑现在没网'
  if (!state.hasKey) return '还没填模型 Key'
  if (state.boot === 'running') return '正在自动诊断与清理预览…'
  if (state.boot === 'failed') return '开机体检失败，用盘根 诊断.cmd'
  if (state.boot === 'done' && state.previewSize) {
    return `${diskLine(state.disk)} · 可回收约 ${state.previewSize} · 说确认才删`
  }
  return diskLine(state.disk)
}

export function buildBootPrompt({ diagnoseStamp, previewStamp, previewSize, logPath }) {
  const foot = footerLines(previewSize).join('\n')
  return [
    'TUI 已经在启动时跑完只读诊断和清理预览，不要再跑 diagnose.ps1 / ops_diagnose / clean.ps1 预览。',
    '用户说「确认」或「执行」之前，绝不 -Execute，绝不 ops_clean execute=true。',
    '没网时不要假装能对话；让人用盘根 诊断.cmd，或在 TUI 输入 /clean 选确认清理。',
    logPath ? `完整输出在 ${logPath}` : '',
    '',
    diagnoseStamp || '',
    previewStamp || '',
    foot,
  ].filter((line, i, arr) => line !== '' || (i > 0 && arr[i - 1] !== '')).join('\n')
}
