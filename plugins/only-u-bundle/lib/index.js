// Only-U 维修命令插件：
//   启动时自动跑 diagnose.ps1 + clean.ps1 预览（不经模型、不 -Execute）
//   /diagnose —— 重跑诊断，报告存 portable\logs
//   /clean    —— 预览条 → 预览戳 → 执行条（默认取消）才带 -Execute
//   /space（/空间）—— 全屏电脑状态；Esc 回对话
// 服务全部经 ctx.get 软探针（TUI profile 根组合由 dsh-base + dsh-tui 提供）。
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { hostname } from 'node:os'
import { join } from 'node:path'
import { Service } from '@deepseek-ai/cordis'
import { registerSpaceScene } from './space.js'
import {
  PROTECT_SHORT,
  shouldSkipAuto,
  footerLines,
  reportStamp as formatStamp,
  nextStep as nextStepFor,
  idleStatus as idleStatusFor,
  buildBootPrompt,
} from './stamp.js'

export const name = 'only-u-bundle'

class OnlyUOps extends Service {
  constructor(ctx) {
    super(ctx, 'only-u-bundle')
  }
}

export default OnlyUOps

const PS = 'powershell.exe'
const RUN_TIMEOUT_MS = 150000
const DIALOG_MS = 600000

function portableDir() {
  return process.env.DSH_HOME ? join(process.env.DSH_HOME, '..', '..') : process.cwd()
}

function runPs1(file, timeoutMs = 0, extraArgs = '') {
  const extra = extraArgs ? ` ${extraArgs}` : ''
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
    `[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); & '${file.replace(/'/g, "''")}'${extra}; exit $LASTEXITCODE`]
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

function isNarrow() {
  return (process.stdout.columns ?? 80) < 80
}

function hasApiKey() {
  if (process.env.ONLY_U_HAS_KEY === '0') return false
  if (process.env.ONLY_U_HAS_KEY === '1') return true
  if (process.env.DEEPSEEK_API_KEY) return true
  try {
    const envFile = join(portableDir(), '.env')
    if (!existsSync(envFile)) return false
    const text = readFileSync(envFile, 'utf8')
    return /^[ \t]*DEEPSEEK_API_KEY[ \t]*=[ \t]*\S+/m.test(text)
  } catch {
    return false
  }
}

function hasNet() {
  if (process.env.ONLY_U_HAS_NET === '0') return false
  if (process.env.ONLY_U_HAS_NET === '1') return true
  return null
}

function formatFree(bytesOrGb, alreadyGb = false) {
  const gb = alreadyGb ? Number(bytesOrGb) : Number(bytesOrGb) / (1024 ** 3)
  if (!Number.isFinite(gb)) return null
  if (gb >= 1) return `${gb.toFixed(1)} GB`
  const mb = gb * 1024
  return `${Math.max(0, Math.round(mb))} MB`
}

function parseCDisk(out) {
  const line = (out ?? '').split(/\r?\n/).find((l) => /^C:\s+total\b/i.test(l.trim()))
  if (!line) return null
  const m = line.match(/free\s+([0-9.,]+)\s*(GB|MB|KB|B)\s*\(([0-9.]+)%\)/i)
  if (!m) return null
  let freeGb = Number(m[1].replace(',', ''))
  const unit = m[2].toUpperCase()
  if (unit === 'MB') freeGb = freeGb / 1024
  else if (unit === 'KB') freeGb = freeGb / (1024 * 1024)
  else if (unit === 'B') freeGb = freeGb / (1024 ** 3)
  const freePct = Number(m[3])
  const usedPct = Number.isFinite(freePct) ? 100 - freePct : null
  return { freeGb, usedPct }
}

function parsePreviewSize(out) {
  const m = (out ?? '').match(/preview total about\s+([0-9.,]+\s*(?:GB|MB|KB|B))/i)
    ?? (out ?? '').match(/将清理约\s+([0-9.,]+\s*(?:GB|MB|KB|B))/i)
  return m ? m[1].replace(',', '') : null
}

function parseFreedSize(out) {
  const m = (out ?? '').match(/actually freed about\s+([0-9.,]+\s*(?:GB|MB|KB|B))/i)
    ?? (out ?? '').match(/本次释放：约\s*[+\-]?([0-9.,]+\s*(?:GB|MB|KB|B))/i)
  return m ? m[1].replace(',', '') : null
}

function diskLine(disk, opts = {}) {
  const narrow = opts.narrow ?? isNarrow()
  if (!disk || disk.freeGb == null) return '还没读到 C 盘'
  const left = formatFree(disk.freeGb, true)
  const used = disk.usedPct
  if (used == null) return narrow ? `C 盘 ${left}` : `C 盘 可用 ${left}`
  if (used >= 90) return narrow ? `C 盘不足 ${left}` : `C 盘空间不足 可用 ${left}`
  if (used >= 70) return narrow ? `C 盘紧张 ${left}` : `C 盘空间紧张 可用 ${left}`
  return narrow ? `C 盘 ${left}` : `C 盘 可用 ${left}`
}

function idleStatus(state) {
  return idleStatusFor(state, diskLine)
}

function nextStep(state) {
  return nextStepFor(state)
}

function bannerText(state) {
  const name = state.computer || hostname() || '这台电脑'
  const os = state.os || 'Windows'
  const net = state.hasNet
  const key = state.hasKey
  const status = net === false
    ? '这台电脑现在没网'
    : !key
      ? '还没填模型 Key'
      : diskLine(state.disk, { narrow: false })
  const lines = [
    'ONLY-U 修机台',
    `这台电脑：${name}     ${os}`,
    `状态：${status}`,
  ]
  if (!isNarrow() && net !== false && key && state.boot === 'idle') {
    lines.push('', '正在自动诊断与清理预览')
  }
  lines.push('', `下一步：${nextStep(state)}`)
  return lines.join('\n')
}

function reportStamp(opts) {
  return formatStamp({ ...opts, narrow: isNarrow(), previewSize: opts.previewSize })
}

function failStamp(reason) {
  return reportStamp({
    kind: '失败',
    conclusion: reason,
    suggest: null,
    next: '再说一次，或用盘根 诊断.cmd',
  })
}

function startWait(status, phrase) {
  const begun = Date.now()
  const paint = () => {
    const sec = Math.max(0, Math.floor((Date.now() - begun) / 1000))
    status?.set('only-u', `${phrase} 已 ${sec} 秒`)
  }
  paint()
  const timer = setInterval(paint, 1000)
  return () => {
    clearInterval(timer)
  }
}

function probeMachine() {
  const ps = `
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$os = Get-CimInstance Win32_OperatingSystem
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
[pscustomobject]@{
  computer = $env:COMPUTERNAME
  os = (($os.Caption) -replace '^Microsoft ', '')
  freeGb = if ($d) { [math]::Round($d.FreeSpace/1GB, 1) } else { $null }
  usedPct = if ($d -and $d.Size -gt 0) { [math]::Round(100 * ($d.Size - $d.FreeSpace) / $d.Size, 1) } else { $null }
} | ConvertTo-Json -Compress
`
  const b64 = Buffer.from(ps, 'utf16le').toString('base64')
  return new Promise((resolve) => {
    const child = spawn(PS, ['-NoProfile', '-EncodedCommand', b64], { stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    child.stdout.setEncoding('utf8')
    child.stdout.on('data', (d) => { out += d })
    child.on('error', () => resolve(null))
    child.on('close', () => {
      try {
        resolve(JSON.parse(out.trim()))
      } catch {
        resolve(null)
      }
    })
  })
}

export function apply(ctx) {
  registerSpaceScene(ctx)

  const commands = ctx.get('commands', false)
  if (!commands) return
  const dialogs = ctx.get('tuiDialogs', false)
  const status = ctx.get('tuiStatus', false)

  try { process.title = 'Only-U 修机台' } catch { /* ignore */ }

  const state = {
    hasKey: hasApiKey(),
    hasNet: hasNet(),
    disk: null,
    computer: hostname(),
    os: '',
    boot: 'idle',
    previewSize: null,
  }
  let bootPromptText = 'TUI 正在自动跑只读诊断和清理预览。未完成前不要自己跑 diagnose。用户说确认之前不要清理。'
  let bootStarted = false

  try {
    ctx.get('systemPrompt', false)?.section({
      name: 'only-u:boot',
      order: 40,
      text: () => bootPromptText,
    })
  } catch { /* old profile without systemPrompt */ }

  const paintIdle = () => {
    status?.set('only-u', idleStatus(state))
  }
  paintIdle()
  probeMachine().then((info) => {
    if (!info) return
    state.computer = info.computer || state.computer
    state.os = info.os || state.os
    if (info.freeGb != null) state.disk = { freeGb: info.freeGb, usedPct: info.usedPct }
    paintIdle()
  })

  const writeBootLog = (text) => {
    try {
      const logDir = join(portableDir(), 'logs')
      mkdirSync(logDir, { recursive: true })
      writeFileSync(join(logDir, 'boot-latest.txt'), text, 'utf8')
      return join(logDir, 'boot-latest.txt')
    } catch {
      return null
    }
  }

  const runDiagnoseCore = async () => {
    const script = join(portableDir(), 'diagnose.ps1')
    if (!existsSync(script)) {
      return { ok: false, stamp: failStamp('找不到诊断脚本'), out: '' }
    }
    const { code, out } = await runPs1(script, RUN_TIMEOUT_MS)
    const logDir = join(portableDir(), 'logs')
    mkdirSync(logDir, { recursive: true })
    writeFileSync(join(logDir, `diagnose-${stamp()}.txt`), out, 'utf8')
    const parsed = parseCDisk(out)
    if (parsed) state.disk = parsed
    if (code !== 0) {
      return { ok: false, stamp: failStamp(`诊断失败（退出码 ${code}）`), out, parsed }
    }
    const left = parsed ? formatFree(parsed.freeGb, true) : '未知'
    const low = parsed && parsed.freeGb < 15
    return {
      ok: true,
      parsed,
      out,
      stamp: reportStamp({
        kind: '诊断',
        conclusion: low ? `C 盘可用 ${left}，低于 15 GB` : `C 盘可用 ${left}`,
        suggest: '先预览清理临时文件',
        next: '正在出清理预览',
        previewSize: state.previewSize,
      }),
    }
  }

  const runCleanPreviewCore = async () => {
    const script = join(portableDir(), 'clean.ps1')
    if (!existsSync(script)) {
      return { ok: false, stamp: failStamp('找不到清理脚本'), previewSize: null, out: '' }
    }
    const { code, out } = await runPs1(script, RUN_TIMEOUT_MS)
    const previewSize = parsePreviewSize(out)
    if (code !== 0) {
      return { ok: false, stamp: failStamp(`预览失败（退出码 ${code}）`), previewSize, out }
    }
    state.previewSize = previewSize
    return {
      ok: true,
      previewSize,
      out,
      stamp: reportStamp({
        kind: '预览',
        conclusion: `可回收约 ${previewSize ?? '一些空间'}，未删除任何文件`,
        next: '确认后才会真正清理',
        previewSize,
      }),
    }
  }

  const runAutoBoot = async () => {
    if (shouldSkipAuto() || bootStarted) return
    bootStarted = true
    state.boot = 'running'
    paintIdle()
    const stop = startWait(status, '正在自动诊断这台电脑…')
    let diagnoseStamp = ''
    let previewStamp = ''
    let previewOut = ''
    let diagnoseOut = ''
    try {
      const diagnose = await runDiagnoseCore()
      diagnoseStamp = diagnose.stamp
      diagnoseOut = diagnose.out || ''
      stop()
      const stopPreview = startWait(status, '正在扫描可回收空间…')
      try {
        const preview = await runCleanPreviewCore()
        previewStamp = preview.stamp
        previewOut = preview.out || ''
        state.boot = (diagnose.ok || preview.ok) ? 'done' : 'failed'
      } finally {
        stopPreview()
      }
    } catch (e) {
      stop()
      state.boot = 'failed'
      diagnoseStamp = failStamp(e?.message ?? String(e))
    }
    const combined = [diagnoseStamp, previewStamp].filter(Boolean).join('\n\n')
    const logPath = writeBootLog(
      [diagnoseOut, previewOut, '', combined].filter((part) => part != null).join('\n'),
    )
    try {
      const stampLines = [
        diagnoseStamp ? diagnoseStamp.split('\n')[0] : '',
        previewStamp ? previewStamp.split('\n')[0] : '',
        ...footerLines(state.previewSize),
      ].filter(Boolean)
      const logDir = join(portableDir(), 'logs')
      mkdirSync(logDir, { recursive: true })
      writeFileSync(join(logDir, 'boot-stamp.txt'), `${stampLines.join('\n')}\n`, 'utf8')
    } catch { /* splash file is best-effort */ }
    bootPromptText = buildBootPrompt({
      diagnoseStamp,
      previewStamp,
      previewSize: state.previewSize,
      logPath: logPath ? 'portable\\logs\\boot-latest.txt' : null,
    })
    paintIdle()
  }

  try {
    ctx.on('agent/session-start', () => { void runAutoBoot() })
  } catch { /* ignore */ }
  try {
    ctx.on('agent/created', () => { void runAutoBoot() })
  } catch { /* ignore */ }
  const bootTimer = setTimeout(() => { void runAutoBoot() }, 400)
  ctx.effect(() => () => clearTimeout(bootTimer))

  const disposeDiagnose = commands.register({
    name: 'diagnose',
    description: '诊断这台电脑，对话里出四行戳，全文进 portable\\logs',
    handler: async () => {
      const stop = startWait(status, '正在诊断这台电脑…')
      try {
        const result = await runDiagnoseCore()
        stop()
        paintIdle()
        return { kind: result.ok ? 'success' : 'error', text: result.stamp }
      } catch (e) {
        stop()
        paintIdle()
        return { kind: 'error', text: failStamp(e?.message ?? String(e)) }
      }
    },
  })
  ctx.effect(() => () => disposeDiagnose())

  const disposeClean = commands.register({
    name: 'clean',
    description: '先预览可回收空间，确认后才会真正清理',
    handler: async () => {
      const previewOk = dialogs
        ? await dialogs.confirm({
            title: '清理预览',
            message: '只扫描可回收空间，不会删除任何文件。',
            confirmLabel: '开始预览',
            cancelLabel: '取消',
            timeoutMs: DIALOG_MS,
          })
        : true
      if (!previewOk) return { kind: 'success', text: '已取消' }

      const stopPreview = startWait(status, '正在扫描可回收空间…')
      let previewSize = null
      try {
        const script = join(portableDir(), 'clean.ps1')
        if (!existsSync(script)) {
          stopPreview()
          paintIdle()
          return { kind: 'error', text: failStamp(`找不到清理脚本`) }
        }
        const { code, out } = await runPs1(script, RUN_TIMEOUT_MS)
        previewSize = parsePreviewSize(out)
        stopPreview()
        paintIdle()
        if (code !== 0) {
          return { kind: 'error', text: failStamp(`预览失败（退出码 ${code}）`) }
        }
      } catch (e) {
        stopPreview()
        paintIdle()
        return { kind: 'error', text: failStamp(e?.message ?? String(e)) }
      }

      const previewStamp = reportStamp({
        kind: '预览',
        conclusion: `可回收约 ${previewSize ?? '一些空间'}，未删除任何文件`,
        next: '确认后才会真正清理',
        previewSize,
      })
      state.previewSize = previewSize

      if (!dialogs) {
        return { kind: 'success', text: previewStamp }
      }

      const choice = await dialogs.select({
        title: '将清理（不可撤销）',
        timeoutMs: DIALOG_MS,
        options: [
          {
            id: 'cancel',
            label: '取消',
            description: `范围：临时文件、回收站、浏览器缓存\n保护：${PROTECT_SHORT} 不动\n约可腾 ${previewSize ?? '一些空间'}`,
          },
          { id: 'execute', label: '确认清理' },
        ],
      })
      if (choice !== 'execute') {
        return { kind: 'success', text: previewStamp }
      }

      const stopExec = startWait(status, '正在清理…')
      try {
        const script = join(portableDir(), 'clean.ps1')
        const { code, out } = await runPs1(script, RUN_TIMEOUT_MS, '-Execute')
        const freed = parseFreedSize(out) ?? previewSize
        const parsed = parseCDisk(out)
        if (parsed) state.disk = parsed
        else {
          const info = await probeMachine()
          if (info?.freeGb != null) state.disk = { freeGb: info.freeGb, usedPct: info.usedPct }
        }
        stopExec()
        paintIdle()
        if (code !== 0) {
          return { kind: 'error', text: failStamp(`清理失败（退出码 ${code}）`) }
        }
        return {
          kind: 'success',
          text: reportStamp({
            kind: '已清理',
            conclusion: `约腾出 ${freed ?? '一些空间'}`,
            next: '可以拔盘，或再说一个问题',
            close: '本次运维完成。可以拔盘，或再说一个问题',
            previewSize: freed ?? previewSize,
          }),
        }
      } catch (e) {
        stopExec()
        paintIdle()
        return { kind: 'error', text: failStamp(e?.message ?? String(e)) }
      }
    },
  })
  ctx.effect(() => () => disposeClean())

  const spaceHandler = () => {
    const scenes = ctx.get('tuiScenes', false)
    if (!scenes) return { kind: 'error', text: failStamp('空间面板不可用') }
    return scenes.open('only-u-space')
      ? { kind: 'success' }
      : { kind: 'error', text: failStamp('空间场景未注册') }
  }
  const disposeSpace = commands.register({
    name: 'space',
    description: '全屏查看 C 盘和电脑状态（Esc 返回）',
    handler: spaceHandler,
  })
  ctx.effect(() => () => disposeSpace())
  const disposeKongjian = commands.register({
    name: 'kongjian',
    description: '全屏查看电脑状态（/space 的拼音别名）',
    handler: spaceHandler,
  })
  ctx.effect(() => () => disposeKongjian())

  const disposeChajian = commands.register({
    name: 'chajian',
    description: '查看已装插件、命令、模型和主题',
    handler: (invocation) => {
      const lines = [bannerText(state), '']
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
      lines.push('【换模型】输入 /provider 三十秒接入第三方模型')
      lines.push('【模式】输入 /preset 切换维修模式')
      lines.push('【主题】输入 /theme 可改回雾蓝')
      return { kind: 'success', text: lines.join('\n') }
    },
  })
  ctx.effect(() => () => disposeChajian())

  ctx.logger?.info('[only-u-bundle] registered: auto-boot /diagnose /clean /space /kongjian /chajian')
}
