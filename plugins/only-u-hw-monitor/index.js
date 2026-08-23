import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadCatalog } from './lib/catalog.js'
import { runTool } from './lib/runner.js'
import { runScript } from './lib/runScript.js'

export const name = 'only-u-hw-monitor'
export const inject = ['tools']

const pkgDir = dirname(fileURLToPath(import.meta.url))

// 内置脚本工具共用输出结构（与 runScript 返回值一致）
const scriptResultSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['exitCode', 'timedOut', 'aborted', 'stdout', 'stderr'],
  properties: {
    exitCode: { type: 'integer' },
    timedOut: { type: 'boolean' },
    aborted: { type: 'boolean' },
    stdout: { type: 'string' },
    stderr: { type: 'string' },
  },
}

const renderScriptResult = (_args, value) => {
  const tail = value.timedOut ? '\n\n[工具超时]' : (value.aborted ? '\n\n[工具被中止]' : '')
  return [{ type: 'text', text: (value.stdout || '') + (value.stderr ? '\n[stderr] ' + value.stderr : '') + tail }]
}

function loadKnowledge() {
  return JSON.parse(readFileSync(join(pkgDir, 'knowledge', 'hw-monitor-tools.json'), 'utf8'))
}

export function apply(ctx, config = {}) {
  const pollTimeoutMs = config.pollTimeoutMs ?? 10000

  ctx.tools.register({
    name: 'mon_tool_list',
    description: '列出可调度的第三方硬件监测工具（宽松协议、随包分发）及各自说明。'
      + '只能列出与调度；未通过验证或文件缺失的工具标记为不可调度'
      + '（可以建议用户手动打开，但不能替你执行）。内置系统诊断请用 ops_diagnose；内置电池/GPU 快查可用 mon_battery_report / mon_nvidia_smi。',
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
            text: '当前没有已收录的第三方硬件监测工具（知识库为空：收录需先完成 CLI 逐条验证）。'
              + '内置诊断请用 ops_diagnose，或建议用户手动打开已安装的同类工具。',
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
    name: 'mon_tool_run',
    description: '执行一个第三方硬件监测工具（只读信息导出类）。'
      + '条目标注风险（如加载内核驱动）时，执行前会向用户弹出确认，未获允许绝不执行。',
    parameters: {
      tool: { type: 'string', required: true, description: '工具 id（来自 mon_tool_list）' },
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
              exitCode: { type: 'integer' },
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
                    path: { type: 'string' },
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
        throw new Error(`未知工具：${args.tool}（先用 mon_tool_list 查看可用工具）`)
      }
      if (!entry.schedulable) {
        throw new Error(`工具 ${entry.name} 不可调度：${entry.unschedulableReason ?? '未通过验证或文件缺失'}`)
      }

      // 写盘/压测类：先审批（dsh-TUI 会弹确认条）
      if (entry.tier === 'red') {
        const approval = ctx.get('approval')
        if (!approval) {
          return { kind: 'tool-denied', outcome: 'unavailable', message: '当前环境没有审批服务，无法确认执行' }
        }
        const outcome = await approval.request({
          agent: exec.agent,
          toolName: 'mon_tool_run',
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

  ctx.tools.register({
    name: 'mon_battery_report',
    description: '生成电池健康报告：型号、设计容量、完全充电容量、健康度、循环次数'
      + '（powercfg /batteryreport，只读，不改任何东西）。'
      + '适用：电池不耐用、续航骤降、验机查电池健康。',
    parameters: {},
    output: {
      schema: scriptResultSchema,
      render: renderScriptResult,
    },
    timeoutMs: 120000,
    async execute(_args, exec) {
      return runScript('battery-report.ps1', [], 120000, exec.signal)
    },
  })

  ctx.tools.register({
    name: 'mon_nvidia_smi',
    description: 'NVIDIA GPU 快查：型号、温度、利用率、显存占用、功耗、驱动版本'
      + '（调用系统自带的 nvidia-smi，只读，不随包分发任何 NVIDIA 组件）。'
      + '适用：怀疑显卡过热/满载；无 NVIDIA GPU 时返回提示。',
    parameters: {},
    output: {
      schema: scriptResultSchema,
      render: renderScriptResult,
    },
    timeoutMs: 30000,
    async execute(_args, exec) {
      return runScript('nvidia-smi.ps1', [], 30000, exec.signal)
    },
  })
}
