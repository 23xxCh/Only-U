// Only-U 维修命令插件（#19）：
//   /diagnose —— 跑 portable\diagnose.ps1，报告存 portable\logs，toast 摘要
//   /clean    —— tuiDialogs 确认后跑清理预览（永不自动 -Execute，铁律）
//   /space（/空间）—— 打开全屏电脑状态场景（#20）
// 服务全部经 ctx.get 软探针获取（TUI profile 根组合由 dsh-base + dsh-tui 提供）。
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { Service } from '@deepseek-ai/cordis'
import { registerSpaceScene } from './space.js'

export const name = 'only-u-bundle'

// dsh-tui 入口行的 inject 链期待名为 only-u-bundle 的「服务」——
// 默认导出 Service 子类、super(ctx, 'only-u-bundle') 即提供服务
// （范本：dsh-tui 的 TuiSceneRuntime，scenes.js）。
class OnlyUOps extends Service {
  constructor(ctx) {
    super(ctx, 'only-u-bundle')
  }
}

export default OnlyUOps

const PS = 'powershell.exe'
const RUN_TIMEOUT_MS = 150000

// DSH_HOME = <U盘>\portable\runtime\dsh（start.cmd 注入）→ portable = 上两级
function portableDir() {
  return process.env.DSH_HOME ? join(process.env.DSH_HOME, '..', '..') : process.cwd()
}

// 跑一个 .ps1（UTF-8 BOM）：stdout 强制 UTF-8，退出码透传
function runPs1(file, timeoutMs = 0) {
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
    `[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); & '${file.replace(/'/g, "''")}'; exit $LASTEXITCODE`]
  return new Promise((resolve, reject) => {
    const child = spawn(PS, psArgs, { cwd: portableDir(), stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    let err = ''
    let timer = null
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (d) => { out += d })
    child.stderr.on('data', (d) => { err += d })
    if (timeoutMs > 0) {
      timer = setTimeout(() => {
        child.kill()
        reject(new Error(`命令超时（${timeoutMs / 1000}s）`))
      }, timeoutMs)
    }
    child.on('error', (e) => {
      if (timer) clearTimeout(timer)
      reject(e)
    })
    child.on('close', (code) => {
      if (timer) clearTimeout(timer)
      resolve({ code, out, err })
    })
  })
}

function stamp() {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}

function tailLines(text, n) {
  return text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(-n).join('\n')
}

export function apply(ctx) {
  registerSpaceScene(ctx)

  const commands = ctx.get('commands', false)
  if (!commands) return
  const dialogs = ctx.get('tuiDialogs', false)
  const status = ctx.get('tuiStatus', false)

  const disposeDiagnose = commands.register({
    name: 'diagnose',
    description: '运行 Only-U 便携诊断（diagnose.ps1），完整报告存入 portable\\logs',
    handler: async () => {
      const clear = status?.set('only-u', '正在诊断（约 1 分钟）…') ?? (() => {})
      try {
        const script = join(portableDir(), 'diagnose.ps1')
        if (!existsSync(script)) {
          clear()
          return { kind: 'error', text: `找不到 ${script}` }
        }
        const { code, out } = await runPs1(script, RUN_TIMEOUT_MS)
        const logDir = join(portableDir(), 'logs')
        mkdirSync(logDir, { recursive: true })
        const report = join(logDir, `diagnose-${stamp()}.txt`)
        writeFileSync(report, out, 'utf8')
        clear()
        return {
          kind: code === 0 ? 'success' : 'error',
          text: `诊断完成（退出码 ${code}）。完整报告：${report}\n${tailLines(out, 6)}`,
        }
      } catch (e) {
        clear()
        return { kind: 'error', text: `诊断失败：${e?.message ?? e}` }
      }
    },
  })
  ctx.effect(() => () => disposeDiagnose())

  const disposeClean = commands.register({
    name: 'clean',
    description: '清理预览：只计算可回收空间，不删除任何文件',
    handler: async () => {
      const ok = dialogs
        ? await dialogs.confirm({
            title: '清理预览',
            message: '只扫描可回收空间并生成预览，不会删除任何文件。继续？',
            confirmLabel: '开始预览',
            cancelLabel: '取消',
          })
        : true
      if (!ok) return { kind: 'success', text: '已取消' }
      const clear = status?.set('only-u', '正在扫描可回收空间…') ?? (() => {})
      try {
        const script = join(portableDir(), 'clean.ps1')
        if (!existsSync(script)) {
          clear()
          return { kind: 'error', text: `找不到 ${script}` }
        }
        const { code, out } = await runPs1(script, RUN_TIMEOUT_MS)
        clear()
        return {
          kind: code === 0 ? 'success' : 'error',
          text: `清理预览完成（退出码 ${code}，未删除任何文件）。\n${tailLines(out, 8)}`,
        }
      } catch (e) {
        clear()
        return { kind: 'error', text: `清理预览失败：${e?.message ?? e}` }
      }
    },
  })
  ctx.effect(() => () => disposeClean())

  const spaceHandler = () => {
    const scenes = ctx.get('tuiScenes', false)
    if (!scenes) return { kind: 'error', text: 'tuiScenes 服务不可用' }
    return scenes.open('only-u-space')
      ? { kind: 'success' }
      : { kind: 'error', text: '空间场景未注册' }
  }
  const disposeSpace = commands.register({
    name: 'space',
    description: '全屏查看电脑状态（CPU/内存/磁盘/GPU 色块面板）',
    handler: spaceHandler,
  })
  ctx.effect(() => () => disposeSpace())
  // 拼音别名（命令名只允许 ^[a-z][a-z0-9_-]*$，中文注册会被静默拒绝——实测）
  const disposeKongjian = commands.register({
    name: 'kongjian',
    description: '全屏查看电脑状态（/space 的拼音别名）',
    handler: spaceHandler,
  })
  ctx.effect(() => () => disposeKongjian())

  // /chajian：给使用者看的插件/命令/模型工具清单（#46）
  // 名称只能 ASCII（dsh-commands 正则），中文入口写进先读我时用 /chajian
  const disposeChajian = commands.register({
    name: 'chajian',
    description: '查看已装插件、可用命令和模型工具的清单',
    handler: (invocation) => {
      const lines = []
      try {
        const entries = [...ctx.loader.entries()]
          .filter((e) => (e.options?.name ?? '').startsWith('only-u-') || (e.options?.name ?? '').includes('only-u'))
          .map((e) => e.options?.name ?? e.options?.id ?? '?')
        lines.push('【插件】' + (entries.length ? entries.join('、') : '无'))
      } catch {
        lines.push('【插件】读取失败')
      }
      try {
        const cmds = ctx.get('commands').list(invocation.agent)
        lines.push('【命令】' + cmds.map((c) => `/${c.name}`).join(' '))
      } catch {
        lines.push('【命令】读取失败')
      }
      try {
        const tools = ctx.get('tools').schemas(invocation.agent)
        const ours = tools.filter((t) => /^(ops_|diag_|mon_|net_|peri_|screen_|stress_|maint_|sys_|dbench_|disk_|clean)/.test(t.name))
        lines.push(`【模型工具】共 ${tools.length} 个，其中 Only-U ${ours.length} 个：`)
        for (const t of ours) lines.push(`  ${t.name} —— ${String(t.description ?? '').split('\n')[0].slice(0, 40)}`)
      } catch {
        lines.push('【模型工具】读取失败')
      }
      lines.push('【换模型】输入 /provider 三十秒接入第三方模型；/preset 切换维修模式')
      return { kind: 'success', text: lines.join('\n') }
    },
  })
  ctx.effect(() => () => disposeChajian())

  ctx.logger?.info('[only-u-bundle] registered: /diagnose /clean /space /kongjian /chajian')
}
