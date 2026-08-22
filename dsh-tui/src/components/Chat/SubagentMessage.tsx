import React from 'react'
import { Box, Text, useAnimationFrame, useTerminalSize } from '../../ui.js'
import type { SubagentRow } from '../../dsh-adapter/channel.js'
import type { Theme } from '../../theme.js'
import { t } from '../../i18n.js'
import { resolvePreset } from '../activityFrames.js'
import { toolNameColor } from '../messages/AssistantToolUseMessage.js'
import { stringWidth } from '../../ink/stringWidth.js'
import { isMinimalMode } from '../../minimalMode.js'

/** The waterfall window is a Kimi Code style constant-height region. */
const WATERFALL_ROWS = 3
/** Card left padding + the `│ ` gutter prefix. */
const WATERFALL_GUTTER = 4

function duration(ms = 0): string {
  const seconds = Math.floor(ms / 1000)
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m${seconds % 60}s`
}
function tokens(row: SubagentRow): string {
  const total = row.tokens?.total ?? ((row.tokens?.input ?? 0) + (row.tokens?.output ?? 0) || 0)
  return total > 0 ? `${total} tok` : '- tok'
}
function status(row: SubagentRow): { glyph: string; label: string; color: keyof Theme | undefined } {
  const minimal = isMinimalMode()
  if (row.status === 'completed') return { glyph: minimal ? '✓' : '🟢', label: t('subagent-status-completed'), color: minimal ? undefined : 'success' }
  if (row.status === 'failed') return { glyph: minimal ? '×' : '🔴', label: t('subagent-status-failed'), color: minimal ? undefined : 'error' }
  if (row.status === 'cancelled') return { glyph: minimal ? '×' : '🔴', label: t('subagent-status-cancelled'), color: minimal ? undefined : 'error' }
  return { glyph: minimal ? '·' : '🟡', label: t('subagent-status-running'), color: minimal ? undefined : 'warning' }
}
/** Hard single-line clip by display width — a wrapped waterfall row would
 * break the constant-height window. */
function clipLine(text: string, maxWidth: number): string {
  if (maxWidth <= 1) return ''
  let width = 0
  let index = 0
  while (index < text.length) {
    // Advance by the next full code point so wide glyphs (CJK, emoji) are
    // never split in half.
    const next = text.codePointAt(index)!
    const char = String.fromCodePoint(next)
    const charWidth = stringWidth(char)
    if (width + charWidth > maxWidth - 1) break
    width += charWidth
    index += char.length
  }
  return index < text.length ? `${text.slice(0, index)}…` : text
}

/**
 * Borderless, fixed-height activity card embedded directly in the transcript
 * (Kimi Code visual language). Running: header + one-line current tool + a
 * constant 3-row waterfall (each row hard-clipped to one terminal line so
 * the card height never changes). Settled: folds to the header line alone
 * (failure keeps one error line). The running glyph reuses the user's
 * working-activity preset (`/activity`), so the indicator follows the same
 * setting as the main spinner.
 */
export function SubagentMessage({ subagent, addMargin, activityFrames, onClick }: {
  subagent: SubagentRow
  addMargin: boolean
  activityFrames?: string
  isExpanded: boolean
  onClick: () => void
}): React.ReactNode {
  const [, time] = useAnimationFrame(120)
  const { columns } = useTerminalSize()
  const info = status(subagent)
  const settled = subagent.status === 'completed' || subagent.status === 'failed' || subagent.status === 'cancelled'
  const elapsed = subagent.completedAt ? subagent.durationMs : Date.now() - subagent.startedAt
  const lastRunning = [...subagent.toolCalls].reverse().find(tool => tool.status === 'running')
  const previousDone = lastRunning
    ? subagent.toolCalls[subagent.toolCalls.indexOf(lastRunning) - 1]
    : subagent.toolCalls[subagent.toolCalls.length - 1]
  const preset = React.useMemo(() => resolvePreset(activityFrames), [activityFrames])
  const activity = settled ? [] : subagent.outputLines.slice(-WATERFALL_ROWS)
  const runningGlyph = preset.frames[Math.floor(time / preset.intervalMs) % preset.frames.length] ?? '·'
  const rowWidth = Math.max(20, (columns ?? 80) - WATERFALL_GUTTER)

  return <Box flexDirection="column" marginTop={addMargin ? 1 : 0} paddingLeft={2} onClick={onClick}>
    <Box flexDirection="row" gap={1}>
      <Text color={info.color}>{settled ? info.glyph : ` ${runningGlyph}`}</Text>
      <Text bold>{`${t('subagent-card-prefix')}${subagent.description}`}</Text>
      <Text dimColor>·</Text><Text>{subagent.model ?? subagent.provider ?? 'default'}</Text>
      {subagent.effort && <><Text dimColor>·</Text><Text dimColor>{subagent.effort}</Text></>}
      <Text dimColor>·</Text><Text dimColor>{duration(elapsed)}</Text>
      <Text dimColor>·</Text><Text dimColor>{tokens(subagent)}</Text>
      <Text dimColor>·</Text><Text dimColor>{subagent.toolCalls.length} tools</Text>
      <Text dimColor>·</Text><Text color={info.color}>{info.label}</Text>
    </Box>
    {!settled && (lastRunning ?? previousDone) !== undefined && (
      <Text wrap="truncate">
        {lastRunning !== undefined ? (
          <>
            {previousDone !== undefined && (
              <>
                <Text dimColor>{'  · '}</Text>
                <Text color="success">✓</Text>
                <Text color={toolNameColor(previousDone.name)}>{previousDone.name}</Text>
                <Text dimColor>{' · '}</Text>
              </>
            )}
            {lastRunning.argsPreview === undefined && (
              <Text color={toolNameColor(lastRunning.name)}>{lastRunning.name}</Text>
            )}
            {lastRunning.argsPreview !== undefined && (
              <>
                <Text color={toolNameColor(lastRunning.name)}>{lastRunning.name}</Text>
                <Text dimColor>{` (${clipLine(lastRunning.argsPreview.replace(/\s+/g, ' ').trim(), Math.max(10, rowWidth - lastRunning.name.length - 6))})`}</Text>
              </>
            )}
          </>
        ) : (
          previousDone !== undefined && (
            <>
              <Text dimColor>{'  · '}</Text>
              <Text color="success">✓</Text>
              <Text color={toolNameColor(previousDone.name)}>{previousDone.name}</Text>
              {previousDone.argsPreview !== undefined && (
                <Text dimColor>{` (${clipLine(previousDone.argsPreview.replace(/\s+/g, ' ').trim(), Math.max(10, rowWidth - previousDone.name.length - 6))})`}</Text>
              )}
            </>
          )
        )}
      </Text>
    )}
    {!settled && Array.from({ length: WATERFALL_ROWS }, (_, index) => (
      <Text key={`${subagent.agentId}-wf-${index}-${time}`} dimColor wrap="truncate">{`  │ ${clipLine(activity[index] ?? '', rowWidth)}`}</Text>
    ))}
    {settled && subagent.status === 'failed' && subagent.error && (
      <Text color="error" wrap="truncate">{`  └ ${clipLine(subagent.error, rowWidth)}`}</Text>
    )}
  </Box>
}
