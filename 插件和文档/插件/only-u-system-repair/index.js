import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadCatalog } from './lib/catalog.js'
import { runTool } from './lib/runner.js'

export const name = 'only-u-system-repair'

const pkgDir = dirname(fileURLToPath(import.meta.url))

function loadKnowledge() {
  return JSON.parse(readFileSync(join(pkgDir, 'knowledge', 'system-repair-tools.json'), 'utf8'))
}

export function apply(ctx, config = {}) {
  const pollTimeoutMs = config.pollTimeoutMs ?? 10000

  ctx.tools.register({
    name: 'sys_tool_list',
    description: '列出可调度的系统修复工具（MIT 协议、随包分发）及各自风险说明。'
      + '只能列出与调度；未通过验证或文件缺失的工具标记为不可调度'
      + '（可以建议用户手动打开，但不能替你执行）。',
    parameters: {},
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['tools'],
        properties: {
          tools: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['id', 'name', 'category', 'description', 'risk', 'schedulable'],
              properties: {
                id: { type: 'string' },
                name: { type: 'string' },
                category: { type: 'string' },
                description: { type: 'string' },
                risk: { type: 'string' },
                schedulable: { type: 'boolean' },
              },
            },
          },
        },
      },
      render: (_args, value) => {
        if (value.tools.length === 0) {
          return [{
            type: 'text',
            text: '当前没有已收录的系统修复工具（知识库为空：收录需先完成 CLI 逐条验证）。'
              + '只能建议用户手动使用已安装的同类工具。',
          }]
        }
        return [{
          type: 'text',
          text: value.tools.map((t) =>
            `- ${t.name}（${t.category}）：${t.description}；风险：${t.risk}${t.schedulable ? '' : '；不可调度'}`).join('\n'),
        }]
      },
    },
    async execute() {
      const catalog = loadCatalog(loadKnowledge())
      return {
        tools: catalog.map((t) => ({
          id: t.id, name: t.name, category: t.category,
          description: t.description, risk: t.risk, schedulable: t.schedulable,
        })),
      }
    },
  })

  ctx.tools.register({
    name: 'sys_tool_run',
    description: '执行一个系统修复工具。写盘/修复类操作执行前会向用户弹出确认'
      + '（工具名、参数、风险说明），未获允许绝不执行。',
    parameters: {
      tool: { type: 'string', required: true, description: '工具 id（来自 sys_tool_list）' },
      params: {
        type: 'object',
        required: false,
        description: '知识库模板允许的填充参数（仅字符串/数字）',
      },
    },
    output: {
      schema: {
        oneOf: [
          {
            type: 'object',
            additionalProperties: false,
            required: ['kind', 'exitCode', 'status', 'timedOut', 'aborted', 'outputs'],
            properties: {
              kind: { type: 'string', const: 'tool-result' },
              exitCode: { type: ['integer', 'null'] },
              status: { type: 'string' },
              timedOut: { type: 'boolean' },
              aborted: { type: 'boolean' },
              outputs: {
                type: 'array',
                items: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['path', 'text', 'truncated'],
                  properties: {
                    path: { type: ['string', 'null'] },
                    text: { type: 'string' },
                    truncated: { type: 'boolean' },
                  },
                },
              },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: ['kind', 'outcome'],
            properties: {
              kind: { type: 'string', const: 'tool-denied' },
              outcome: { type: 'string', enum: ['rejected', 'cancelled', 'unavailable'] },
              message: { type: 'string' },
            },
          },
        ],
      },
      render: (_args, value) => {
        if (value.kind === 'tool-denied') {
          return [{ type: 'text', text: `[工具未执行：用户未批准（${value.outcome}）] ${value.message ?? ''}` }]
        }
        const extra = value.timedOut ? '（超时）' : value.aborted ? '（已中止）' : ''
        return [{ type: 'text', text: `[退出码 ${value.exitCode}] ${value.status}${extra}` }]
      },
    },
    timeoutMs: 1800000,
    async execute(args, exec) {
      const catalog = loadCatalog(loadKnowledge())
      const entry = catalog.find((e) => e.id === args.tool)
      if (!entry) {
        throw new Error(`未知工具：${args.tool}（先用 sys_tool_list 查看可用工具）`)
      }
      if (!entry.schedulable) {
        throw new Error(`工具 ${entry.name} 不可调度：${entry.unschedulableReason ?? '未通过验证或文件缺失'}`)
      }

      // 写盘/修复类：先审批（dsh-TUI 会弹确认条）
      if (entry.tier === 'red') {
        const approval = ctx.get('approval')
        if (!approval) {
          return { kind: 'tool-denied', outcome: 'unavailable', message: '当前环境没有审批服务，无法确认执行' }
        }
        const outcome = await approval.request({
          agent: exec.agent,
          toolName: 'sys_tool_run',
          callId: exec.callId,
          reason: `执行 ${entry.name}：参数 ${JSON.stringify(args.params ?? {})}。风险：${entry.risk}。是否执行？`,
          signal: exec.signal,
        })
        if (outcome !== 'allowed-once') {
          return { kind: 'tool-denied', outcome, message: `用户未批准执行 ${entry.name}` }
        }
      }

      return runTool(entry, args.params ?? {}, exec.signal, { pollTimeoutMs })
    },
  })
}

