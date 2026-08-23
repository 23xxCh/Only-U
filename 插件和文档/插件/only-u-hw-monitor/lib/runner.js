import { spawn } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { describeExit } from './exitcodes.js'

/**
 * 填充参数模板：${key} → params[key]（仅字符串/数字；缺失即抛错）。
 * 返回值直接作为 argv 传给 spawn(shell:false)——每个 token 都是独立参数，
 * 参数里带空格/分号等特殊字符也不会有命令注入面。
 */
export function fillTemplate(tokens, params) {
  return tokens.map((tok) => tok.replace(/\$\{(\w+)\}/g, (_m, key) => {
    const v = params[key]
    if (typeof v !== 'string' && typeof v !== 'number') {
      throw new Error(`参数 ${key} 缺失或类型不是字符串/数字`)
    }
    return String(v)
  }))
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function readOutFile(path, maxBytes) {
  try {
    if (!existsSync(path)) return null
    const buf = readFileSync(path)
    const text = buf.toString('utf8')
    return {
      path,
      text: text.length > maxBytes ? text.slice(0, maxBytes) : text,
      truncated: text.length > maxBytes,
    }
  } catch { return null }
}

/**
 * 执行一个知识库条目：
 * - spawn(shell:false) + windowsHide；entry.timeoutMs 超时 / signal 中止 → taskkill 杀进程树
 * - outPattern 结果文件有界轮询（pollTimeoutMs）
 * - 退出码经 exitCodes 表翻译为 status；stdout/结果文件进 outputs（超 maxOutBytes 截断）
 */
export async function runTool(entry, params, signal, { pollTimeoutMs = 10000 } = {}) {
  const args = fillTemplate(entry.argTemplate ?? [], params)
  const outFile = entry.outPattern
    ? fillTemplate([entry.outPattern], params)[0]
    : null

  const result = {
    kind: 'tool-result',
    exitCode: null,
    status: 'unknown',
    timedOut: false,
    aborted: false,
    stdout: '',
    stderr: '',
    outputs: [],
  }

  let settled = false
  const killTree = (proc) => {
    if (proc.pid) spawn('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { stdio: 'ignore' })
  }

  await new Promise((resolve) => {
    const proc = spawn(entry.exePath, args, { shell: false, windowsHide: true })

    const finish = () => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      signal?.removeEventListener('abort', onAbort)
      resolve()
    }

    const timer = entry.timeoutMs > 0 ? setTimeout(() => {
      result.timedOut = true
      killTree(proc)
      finish()
    }, entry.timeoutMs) : null

    const onAbort = () => {
      result.aborted = true
      killTree(proc)
      finish()
    }
    signal?.addEventListener('abort', onAbort, { once: true })

    proc.stdout.setEncoding('utf8')
    proc.stderr.setEncoding('utf8')
    proc.stdout.on('data', (d) => { result.stdout += d })
    proc.stderr.on('data', (d) => { result.stderr += d })
    proc.on('error', (err) => { result.stderr += String(err); finish() })
    proc.on('close', (code) => { result.exitCode = code; finish() })
  })

  if (outFile) {
    const deadline = Date.now() + pollTimeoutMs
    while (!existsSync(outFile) && Date.now() < deadline) await sleep(300)
  }

  const maxBytes = entry.maxOutBytes ?? 524288
  if (result.stdout) {
    result.outputs.push({
      path: null,
      text: result.stdout.length > maxBytes ? result.stdout.slice(0, maxBytes) : result.stdout,
      truncated: result.stdout.length > maxBytes,
    })
  }
  if (outFile) {
    const f = readOutFile(outFile, maxBytes)
    if (f) result.outputs.push(f)
  }

  result.status = result.timedOut ? 'timeout'
    : result.aborted ? 'aborted'
      : describeExit(entry, result.exitCode)
  return result
}
