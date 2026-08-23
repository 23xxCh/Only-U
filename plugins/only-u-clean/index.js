import { runScript } from './lib/runScript.js'
import { parseBlocked, summarizePreview } from './lib/parse.js'

export const name = 'only-u-clean'
export const inject = ['tools']

export function apply(ctx, config = {}) {
  const previewTimeoutMs = config.cleanPreviewTimeoutMs ?? 240000
  const executeTimeoutMs = config.cleanExecuteTimeoutMs ?? 600000

  ctx.tools.register({
    name: 'ops_clean',
    description: '清理 Windows 垃圾文件。execute=false 只预览（只读，返回可回收大小与路径清单）；'
      + 'execute=true 真实删除，执行前会向用户弹出确认，未获允许绝不执行。'
      + '只清理白名单：TEMP 临时文件、缩略图缓存、WER 错误报告、Windows Update 下载缓存、回收站。'
      + '桌面/文档/下载/图片永不清理。',
    parameters: { type: 'object', properties: {
      execute: { type: 'boolean',
        description: 'false=预览（只读，默认）。true=按预览清单真实删除；'
          + '会弹出用户确认，用户拒绝则返回 denied 而不是执行。', }
    } },
    output: {
      schema: {
        oneOf: [
          {
            type: 'object',
            additionalProperties: false,
            required: ['kind', 'exitCode', 'timedOut', 'aborted', 'stdout', 'stderr', 'blocked'],
            properties: {
              kind: { type: 'string', const: 'clean-preview' },
              exitCode: { type: 'integer' },
              timedOut: { type: 'boolean' },
              aborted: { type: 'boolean' },
              stdout: { type: 'string' },
              stderr: { type: 'string' },
              blocked: { type: 'array', items: { type: 'string' } },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: ['kind', 'exitCode', 'timedOut', 'aborted', 'stdout', 'stderr', 'logPath'],
            properties: {
              kind: { type: 'string', const: 'clean-executed' },
              exitCode: { type: 'integer' },
              timedOut: { type: 'boolean' },
              aborted: { type: 'boolean' },
              stdout: { type: 'string' },
              stderr: { type: 'string' },
              logPath: { type: 'string' },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: ['kind', 'outcome'],
            properties: {
              kind: { type: 'string', const: 'clean-denied' },
              outcome: { type: 'string', enum: ['rejected', 'cancelled', 'unavailable'] },
              message: { type: 'string' },
            },
          },
        ],
      },
      render: (_args, value) => {
        if (value.kind === 'clean-denied') {
          return [{ type: 'text', text: `[清理未执行：用户未批准（${value.outcome}）] ${value.message ?? ''}` }]
        }
        if (value.kind === 'clean-preview') {
          const guard = value.blocked.length > 0
            ? `\n\n被保护跳过（永不清理）：${value.blocked.join('；')}` : ''
          return [{ type: 'text', text: `[清理预览（只读，未删除任何文件）]\n${value.stdout}${guard}` }]
        }
        return [{ type: 'text', text: `[清理已执行] 日志：${value.logPath ?? '见 stdout'}\n${value.stdout}` }]
      },
    },
    timeoutMs: executeTimeoutMs,
    async execute(args, exec) {
      const doExecute = args.execute === true

      // 1. 无论预览还是执行，都先跑一次全新预览（不信任模型转述）
      const preview = await runScript('clean.ps1', [], previewTimeoutMs, exec.signal)
      if (preview.timedOut || preview.aborted) {
        return { kind: 'clean-preview', blocked: parseBlocked(preview.stdout), ...preview }
      }

      // 2. 只预览：直接返回
      if (!doExecute) {
        return { kind: 'clean-preview', blocked: parseBlocked(preview.stdout), ...preview }
      }

      // 3. 执行前必须过审批服务（dsh-TUI 会弹确认条）
      const approval = ctx.get('approval')
      if (!approval) {
        return { kind: 'clean-denied', outcome: 'unavailable', message: '当前环境没有审批服务，无法确认删除' }
      }
      const outcome = await approval.request({
        agent: exec.agent,
        toolName: 'ops_clean',
        callId: exec.callId,
        reason: `清理执行确认：${summarizePreview(preview.stdout)}（白名单：TEMP/缩略图缓存/WER/更新缓存/回收站）。`
          + '桌面、文档、下载、图片永不清理。允许本次删除？',
        signal: exec.signal,
      })

      // 4. 仅 allowed-once 才执行，其余一律拒绝（fail-closed）
      if (outcome !== 'allowed-once') {
        return { kind: 'clean-denied', outcome, message: '用户未批准清理执行' }
      }

      const r = await runScript('clean.ps1', ['-Execute'], executeTimeoutMs, exec.signal)
      const logPath = r.stdout.match(/log:\s*(.+\.log)/)?.[1] ?? null
      return { kind: 'clean-executed', logPath, ...r }
    },
  })
}
