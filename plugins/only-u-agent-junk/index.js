import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { runScript } from './lib/runScript.js'
import { requestApproval } from './lib/approve.js'

export const name = 'only-u-agent-junk'
export const inject = ['tools']

const pkgDir = dirname(fileURLToPath(import.meta.url))

// 脚本类工具共用输出结构（与 runScript 返回值一致）
const scriptResultSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['kind', 'exitCode', 'timedOut', 'aborted', 'stdout', 'stderr'],
  properties: {
    kind: { type: 'string' },
    exitCode: { type: 'integer' },
    timedOut: { type: 'boolean' },
    aborted: { type: 'boolean' },
    stdout: { type: 'string' },
    stderr: { type: 'string' },
  },
}

const deniedSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['kind', 'outcome'],
  properties: {
    kind: { type: 'string', const: 'tool-denied' },
    outcome: { type: 'string', enum: ['rejected', 'cancelled', 'unavailable'] },
    message: { type: 'string' },
  },
}

const renderScript = (prefix) => (_args, value) => {
  if (value.kind === 'tool-denied') {
    return [{ type: 'text', text: `[工具未执行：用户未批准（${value.outcome}）] ${value.message ?? ''}` }]
  }
  const tail = value.timedOut ? '\n\n[工具超时]' : (value.aborted ? '\n\n[工具被中止]' : '')
  return [{ type: 'text', text: `${prefix}${value.stdout || ''}${value.stderr ? '\n[stderr] ' + value.stderr : ''}${tail}` }]
}

function loadKnowledge() {
  return JSON.parse(readFileSync(join(pkgDir, 'knowledge', 'agent-footprints.json'), 'utf8'))
}

// 从 clean.ps1 预览输出里提取可回收总量，供审批理由展示
function summarizeCleanPreview(stdout) {
  const m = stdout.match(/green total[^\d]*([\d.]+\s*[KMG]?B)/i)
  return m ? m[1] : '未知大小'
}

export function apply(ctx, config = {}) {
  const scanTimeoutMs = config.scanTimeoutMs ?? 240000
  const cleanPreviewTimeoutMs = config.cleanPreviewTimeoutMs ?? 240000
  const cleanExecuteTimeoutMs = config.cleanExecuteTimeoutMs ?? 900000
  const migrateTimeoutMs = config.migrateTimeoutMs ?? 1800000

  ctx.tools.register({
    name: 'ops_agent_junk_scan',
    description: '扫描 AI 编程工具（Codex/Claude Code/WorkBuddy/Continue/Cursor/Antigravity/OpenCode 等 60+ 足迹）'
      + '在 C 盘的垃圾占用，输出分类报告 JSON：每条足迹的工具名、路径、实测大小、'
      + '风险档位（green=缓存/日志/更新残留可安全清，yellow=可重建索引/过期缓存，'
      + 'red=会话历史/配置/登录态只可迁移）与处理建议。'
      + '只读扫描，不删任何文件；只扫 %USERPROFILE%/%LOCALAPPDATA%/%APPDATA% 下知识库已知路径，不递归全盘。'
      + '把报告转成用户可读的中文总结（按大小排序，突出大头与可立即回收项）。',
    parameters: {},
    output: {
      schema: scriptResultSchema,
      render: renderScript('[AI 工具足迹扫描（只读）]\n'),
    },
    timeoutMs: scanTimeoutMs,
    async execute(_args, exec) {
      const r = await runScript('scan.ps1', [], scanTimeoutMs, exec.signal)
      return { kind: 'scan-result', ...r }
    },
  })

  ctx.tools.register({
    name: 'ops_agent_junk_clean',
    description: '清理 AI 编程工具在 C 盘的垃圾。execute=false（默认）只预览（只读，返回绿档可回收清单）；'
      + 'execute=true 真实删除，执行前会向用户弹出确认，未获允许绝不执行。'
      + '只清绿档：Cache*/GPUCache/logs/traces/更新器残留等自动重建类。'
      + '红档（会话历史/配置/登录态，如 sessions/history/auth/credentials/config）'
      + '永不进入删除枚举（脚本内硬编码黑名单 + 知识库双保险）；黄档（可重建索引）不在本工具范围。'
      + 'AI 工具的会话历史视同用户文档，与 Desktop/Documents 同级保护。',
    parameters: {
      execute: {
        type: 'boolean',
        required: false,
        description: 'false=预览（只读，默认）。true=按绿档清单真实删除；'
          + '会弹出用户确认，用户拒绝则返回 tool-denied 而不是执行。',
      },
    },
    output: {
      schema: { oneOf: [scriptResultSchema, deniedSchema] },
      render: renderScript(''),
    },
    timeoutMs: cleanExecuteTimeoutMs,
    async execute(args, exec) {
      const doExecute = args.execute === true

      // 1. 无论预览还是执行，都先跑一次全新预览（不信任模型转述）
      const preview = await runScript('clean.ps1', [], cleanPreviewTimeoutMs, exec.signal)
      if (!doExecute) {
        return { kind: 'clean-preview', ...preview }
      }
      if (preview.timedOut || preview.aborted) {
        return { kind: 'clean-preview', ...preview }
      }

      // 2. 执行前必须过审批服务（dsh-TUI 会弹确认条），fail-closed
      const denied = await requestApproval(ctx, exec, 'ops_agent_junk_clean',
        `AI 工具垃圾清理执行确认：绿档可回收约 ${summarizeCleanPreview(preview.stdout)}`
        + '（Cache*/GPUCache/logs/traces/更新器残留等自动重建类）。'
        + '会话历史/配置/登录态（红档）永不清理。允许本次删除？')
      if (denied) return denied

      // 3. 放行后真实执行
      const r = await runScript('clean.ps1', ['-Execute'], cleanExecuteTimeoutMs, exec.signal)
      return { kind: 'clean-executed', ...r }
    },
  })

  ctx.tools.register({
    name: 'ops_agent_migrate',
    description: 'AI 工具数据 junction 迁移向导：把 targetId 对应的工具数据目录从 C 盘迁到 destRoot'
      + '（robocopy /E /COPY:DAT → 逐字节抽验 3 个文件 → mklink /J 建联接 → 验证链接可读 → '
      + '确认链接工作后才删原实体目录，中途任一步失败即中止并保留原件）。'
      + 'targetId 来自 ops_agent_junk_scan 报告（如 codex-sessions/claude-sessions/continue-index）。'
      + '先退出对应工具再迁移。会话历史等红档数据推荐用本工具搬到其他盘而不是删除。'
      + '执行前会向用户弹出确认，未获允许绝不执行。'
      + '坑位提示：Codex 桌面版硬编码忽略 CODEX_HOME（只能 junction）；'
      + '~\\.cache\\codex-runtimes 须单独 junction（不随 CODEX_HOME 走）。',
    parameters: {
      targetId: {
        type: 'string',
        required: true,
        description: '知识库足迹 id（来自 ops_agent_junk_scan 报告的 id 字段）',
      },
      destRoot: {
        type: 'string',
        required: true,
        description: '目标盘根目录（如 D:\\AI-Tools），须在其他磁盘且有足够空间',
      },
    },
    output: {
      schema: { oneOf: [scriptResultSchema, deniedSchema] },
      render: renderScript(''),
    },
    timeoutMs: migrateTimeoutMs,
    async execute(args, exec) {
      const knowledge = loadKnowledge()
      const entry = knowledge.find((e) => e.id === args.targetId)
      if (!entry) {
        throw new Error(`未知足迹 id：${args.targetId}（先用 ops_agent_junk_scan 查看可用 id）`)
      }
      if (entry.action !== 'migrate') {
        throw new Error(`足迹 ${entry.id}（${entry.name}）的处理建议是 ${entry.action}，不适用迁移：${entry.notes}`)
      }
      if (!args.destRoot || !/^[A-Za-z]:\\/.test(args.destRoot)) {
        throw new Error('destRoot 须是绝对路径（如 D:\\AI-Tools）')
      }

      const baseArgs = ['-TargetId', args.targetId, '-DestRoot', args.destRoot]

      // 1. 先跑一次预览（只读：定位源目录、测大小、给迁移计划）
      const preview = await runScript('migrate.ps1', baseArgs, migrateTimeoutMs, exec.signal)
      if (preview.timedOut || preview.aborted || /source.*not found|源目录未找到/i.test(preview.stdout + preview.stderr)) {
        return { kind: 'migrate-preview', ...preview }
      }

      // 2. 执行前必须过审批服务（dsh-TUI 会弹确认条），fail-closed
      const denied = await requestApproval(ctx, exec, 'ops_agent_migrate',
        `junction 迁移确认：${entry.name} → ${args.destRoot}`
        + `（预览：${preview.stdout.split('\n').filter((l) => /plan|source|size|源|计划/i.test(l)).slice(0, 3).join('；')}）。`
        + 'robocopy 复制并逐字节抽验后建联接，链接验证可读才删原实体目录。请先退出对应工具。允许执行？')
      if (denied) return denied

      // 3. 放行后真实执行
      const r = await runScript('migrate.ps1', [...baseArgs, '-Execute'], migrateTimeoutMs, exec.signal)
      return { kind: 'migrate-executed', ...r }
    },
  })
}
