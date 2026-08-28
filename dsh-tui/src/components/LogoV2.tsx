import React from 'react'
import { existsSync, readFileSync } from 'node:fs'
import { hostname } from 'node:os'
import { join } from 'node:path'
import { Box, Text } from '../ui.js'
import { getTheme } from '../theme.js'
import { useTheme } from './design-system/ThemeProvider.js'
import { parseRGB } from './Spinner/spinnerUtils.js'
import { renderBigText } from './bigfont.js'
import { BRAND, FLASH, ICE, sweep } from './shimmer.js'

function nextStep(): string {
  if (process.env.ONLY_U_HAS_NET === '0') return '先用盘根 诊断.cmd（不用网）'
  if (process.env.ONLY_U_HAS_KEY === '0') return '输入 /provider 填 Key，或先用盘根 诊断.cmd'
  return '正在自动诊断与清理预览；看完后输入「确认」才删除'
}

function statusLine(): string | null {
  if (process.env.ONLY_U_HAS_NET === '0') return '这台电脑现在没网'
  if (process.env.ONLY_U_HAS_KEY === '0') return '还没填模型 Key'
  return null
}

function bootStampPath(): string | null {
  const home = process.env.DSH_HOME
  if (!home) return null
  return join(home, '..', '..', 'logs', 'boot-stamp.txt')
}

function readBootStamp(): string[] {
  try {
    const path = bootStampPath()
    if (!path || !existsSync(path)) return []
    return readFileSync(path, 'utf8').split(/\r?\n/).map((line) => line.trim()).filter(Boolean).slice(0, 8)
  } catch {
    return []
  }
}

export function LogoV2({
  cwd,
}: {
  model: string
  effort?: string | undefined
  cwd: string
  skipIntro?: boolean
  tip?: unknown
  whale?: boolean
  drift?: unknown
}): React.ReactNode {
  const [themeName] = useTheme()
  const theme = getTheme(themeName)
  const wordmarkRGB = parseRGB(theme.claude) ?? BRAND
  const taglineRGB = parseRGB(theme.claudeBlue_FOR_SYSTEM_SPINNER) ?? ICE
  const big = renderBigText('ONLY-U', 0, wordmarkRGB, taglineRGB, FLASH, 60)
  const name = process.env.COMPUTERNAME || hostname() || '这台电脑'
  const status = statusLine()
  const [stampLines, setStampLines] = React.useState<string[]>(() => readBootStamp())

  React.useEffect(() => {
    const tick = () => {
      const lines = readBootStamp()
      if (lines.length > 0) setStampLines(lines)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])

  return (
    <Box flexDirection="column" marginTop={1}>
      <Text>{sweep('ONLY-U 修机台', 0, wordmarkRGB, ICE, 60)}</Text>
      {big.map((row, index) => (
        <Text key={`ou-${index}`} wrap="truncate-end">
          {row}
        </Text>
      ))}
      <Text dimColor wrap="truncate-end">
        {`这台电脑：${name}`}
      </Text>
      {status ? <Text>{`状态：${status}`}</Text> : null}
      <Text dimColor wrap="truncate-end">
        {cwd}
      </Text>
      <Box marginTop={1}>
        <Text>{`下一步：${stampLines.length ? '看完预览后输入「确认」才会删除' : nextStep()}`}</Text>
      </Box>
      {stampLines.map((line, index) => (
        <Text key={`boot-${index}`} wrap="truncate-end">
          {line}
        </Text>
      ))}
    </Box>
  )
}
