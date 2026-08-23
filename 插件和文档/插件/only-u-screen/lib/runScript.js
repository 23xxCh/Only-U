import { spawn } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const pkgDir = dirname(dirname(fileURLToPath(import.meta.url)))

/**
 * 用 powershell.exe 跑包内 ps1 脚本，返回结构化结果。
 * - UTF-8 解码输出（脚本内已设 [Console]::OutputEncoding = UTF8）
 * - timeoutMs 超时或 signal 中止 → taskkill /T /F 杀整棵进程树
 * - 不抛异常：任何失败都作为结构化结果返回，绝不拖垮 agent-loop
 */
export async function runScript(relPath, args = [], timeoutMs = 0, signal = undefined) {
  const ps1 = join(pkgDir, 'assets', relPath)
  const result = { exitCode: null, stdout: '', stderr: '', timedOut: false, aborted: false }

  let settled = false
  const killTree = (proc) => {
    if (proc.pid) spawn('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { stdio: 'ignore' })
  }

  return new Promise((resolve) => {
    const proc = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', ps1, ...args,
    ], { windowsHide: true })

    const finish = () => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      signal?.removeEventListener('abort', onAbort)
      resolve(result)
    }

    const timer = timeoutMs > 0 ? setTimeout(() => {
      result.timedOut = true
      killTree(proc)
      finish()
    }, timeoutMs) : null

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
}
