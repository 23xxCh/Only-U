// /空间 全屏场景：CPU / 内存 / 磁盘 / GPU 色块面板（#20）
// React 契约：hooks 与 createElement 必须用宿主注入的 React（scenes.d.ts 硬性要求）
import { spawn } from 'node:child_process'

const PS = 'powershell.exe'

// 一次 CIM 收集全部数据，UTF-16LE base64 走 -EncodedCommand，避开引号地狱
const COLLECT_PS = `
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$gpu = Get-CimInstance Win32_VideoController | Sort-Object AdapterRAM -Descending | Select-Object -First 1
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
  [pscustomobject]@{ id = $_.DeviceID; used = [math]::Round(($_.Size - $_.FreeSpace)/1GB, 1); total = [math]::Round($_.Size/1GB, 1) }
}
[pscustomobject]@{
  cpuName = $cpu.Name
  cpuLoad = $cpu.LoadPercentage
  memTotal = [math]::Round($os.TotalVisibleMemorySize/1MB, 1)
  memFree = [math]::Round($os.FreePhysicalMemory/1MB, 1)
  gpuName = $gpu.Name
  disks = @($disks)
} | ConvertTo-Json -Compress
`

export function collectSpace() {
  const b64 = Buffer.from(COLLECT_PS, 'utf16le').toString('base64')
  return new Promise((resolve, reject) => {
    const child = spawn(PS, ['-NoProfile', '-EncodedCommand', b64], { stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    let err = ''
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (d) => { out += d })
    child.stderr.on('data', (d) => { err += d })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code !== 0 && !out.trim()) {
        reject(new Error(err.trim() || `PowerShell 退出码 ${code}`))
        return
      }
      try {
        resolve(JSON.parse(out.trim()))
      } catch (e) {
        reject(new Error(`空间数据解析失败：${out.slice(0, 200)}`))
      }
    })
  })
}

// 色块条：绿 <70% / 黄 <90% / 红 ≥90%，ANSI 256 色直接进 Text 子串
function bar(used, total, width) {
  const ratio = total > 0 ? Math.min(1, used / total) : 0
  const filled = Math.round(ratio * width)
  const color = ratio >= 0.9 ? '38;5;196' : ratio >= 0.7 ? '38;5;220' : '38;5;46'
  return `[${color}m` + '█'.repeat(filled)
    + '[38;5;240m' + '░'.repeat(width - filled) + '[0m'
}

function SpaceScene({ React, ui, close }) {
  const { Box, Text, useInput, useTerminalSize } = ui
  const { columns } = useTerminalSize()
  const [data, setData] = React.useState(null)
  const [error, setError] = React.useState(null)
  const [seq, setSeq] = React.useState(0)

  React.useEffect(() => {
    let alive = true
    setError(null)
    collectSpace()
      .then((d) => { if (alive) setData(d) })
      .catch((e) => { if (alive) setError(String(e?.message ?? e)) })
    return () => { alive = false }
  }, [seq])

  useInput((input, key) => {
    if (key.escape || input === 'q') { close(); return }
    if (input === 'r') setSeq((s) => s + 1)
  })

  const el = React.createElement
  const bw = Math.max(10, Math.min(30, (columns ?? 80) - 32))

  const rows = [
    el(Text, { key: 'title', bold: true }, ' Only-U 电脑状态（r 刷新 · Esc/q 退出）'),
    el(Text, { key: 'pad', children: ' ' }),
  ]
  if (error) {
    rows.push(el(Text, { key: 'err' }, ` 读取失败：${error}`))
    return el(Box, { flexDirection: 'column', paddingX: 1, children: rows })
  }
  if (!data) {
    rows.push(el(Text, { key: 'loading' }, ' 正在读取电脑状态…'))
    return el(Box, { flexDirection: 'column', paddingX: 1, children: rows })
  }

  const memUsed = Math.max(0, data.memTotal - data.memFree)
  rows.push(el(Text, { key: 'cpu', bold: true }, ` CPU  ${data.cpuLoad}%`))
  rows.push(el(Text, { key: 'cpu-bar', children: `  ${bar(data.cpuLoad, 100, bw)}` }))
  rows.push(el(Text, { key: 'pad1', children: ' ' }))
  rows.push(el(Text, { key: 'mem', bold: true }, ` 内存 ${memUsed.toFixed(1)} / ${data.memTotal} GB`))
  rows.push(el(Text, { key: 'mem-bar', children: `  ${bar(memUsed, data.memTotal, bw)}` }))
  rows.push(el(Text, { key: 'pad2', children: ' ' }))
  for (const d of data.disks ?? []) {
    rows.push(el(Text, { key: `d-${d.id}`, bold: true }, ` 磁盘 ${d.id}  ${d.used} / ${d.total} GB`))
    rows.push(el(Text, { key: `d-${d.id}-bar`, children: `  ${bar(d.used, d.total, bw)}` }))
  }
  rows.push(el(Text, { key: 'pad3', children: ' ' }))
  rows.push(el(Text, { key: 'gpu', bold: true }, ` 显卡 ${data.gpuName ?? '未识别'}`))
  return el(Box, { flexDirection: 'column', paddingX: 1, children: rows })
}

export function registerSpaceScene(ctx) {
  const scenes = ctx.get('tuiScenes', false)
  if (!scenes) return
  const dispose = scenes.register({
    id: 'only-u-space',
    title: 'Only-U 空间',
    component: SpaceScene,
  }, ctx)
  ctx.effect(() => () => dispose())
}
