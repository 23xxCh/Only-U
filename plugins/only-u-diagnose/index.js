import { runScript } from './lib/runScript.js'
import { parseRedFlags } from './lib/parse.js'

export const name = 'only-u-diagnose'
export const inject = ['tools']

export function apply(ctx, config = {}) {
  const timeoutMs = config.diagnoseTimeoutMs ?? 240000

  ctx.tools.register({
    name: 'ops_diagnose',
    description: '对当前 Windows 电脑做一次只读系统诊断：磁盘空间、内存压力、'
      + 'TOP5 占内存进程、启动项数量、临时目录、近 7 天关键系统事件、打印机、'
      + 'PnP 驱动异常、SMART 健康。只读，不修改任何东西。'
      + '返回完整报告文本与红灯区列表，模型负责把它整理成用户能看懂的中文结论。',
    parameters: { type: 'object', properties: {} },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['kind', 'exitCode', 'timedOut', 'aborted', 'stdout', 'stderr', 'redFlags'],
        properties: {
          kind: { type: 'string', const: 'diagnose' },
          exitCode: { type: 'integer' },
          timedOut: { type: 'boolean' },
          aborted: { type: 'boolean' },
          stdout: { type: 'string' },
          stderr: { type: 'string' },
          redFlags: { type: 'array', items: { type: 'string' } },
        },
      },
      render: (_args, value) => {
        const head = value.redFlags.length > 0
          ? `【红灯区 ${value.redFlags.length} 项】${value.redFlags.join('；')}\n\n`
          : ''
        const tail = value.timedOut
          ? '\n\n[诊断超时，部分项目未完成]'
          : (value.aborted ? '\n\n[诊断被中止]' : '')
        return [{ type: 'text', text: head + value.stdout + tail }]
      },
    },
    timeoutMs,
    async execute(_args, exec) {
      const r = await runScript('diagnose.ps1', [], timeoutMs, exec.signal)
      return { kind: 'diagnose', redFlags: parseRedFlags(r.stdout), ...r }
    },
  })
}
