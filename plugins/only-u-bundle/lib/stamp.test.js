import assert from 'node:assert/strict'
import {
  shouldSkipAuto,
  footerLines,
  reportStamp,
  nextStep,
  idleStatus,
  buildBootPrompt,
} from './stamp.js'

assert.equal(shouldSkipAuto({}), false)
assert.equal(shouldSkipAuto({ ONLY_U_SKIP_AUTO: '1' }), true)

const foot = footerLines('4.2 GB')
assert.ok(foot[0].includes('能清多少'))
assert.ok(foot[0].includes('4.2 GB'))
assert.ok(foot[1].includes('不碰什么'))
assert.ok(foot[2].includes('说确认才删'))
assert.equal(footerLines(null)[0], '能清多少：见清理预览')

const stamp = reportStamp({
  kind: '预览',
  conclusion: '可回收约 4.2 GB，未删除任何文件',
  next: '确认后才会真正清理',
  previewSize: '4.2 GB',
})
assert.ok(stamp.includes('[预览]'))
assert.ok(stamp.includes('能清多少：约 4.2 GB'))
assert.ok(stamp.includes('说确认才删'))
assert.ok(!stamp.includes('-Execute'))

assert.equal(
  nextStep({ hasNet: true, hasKey: true, boot: 'idle' }),
  '正在自动诊断与清理预览…',
)
assert.equal(
  nextStep({ hasNet: true, hasKey: true, boot: 'done' }),
  '看完预览后输入「确认」才会删除',
)
assert.ok(nextStep({ hasNet: false, hasKey: true, boot: 'done' }).includes('诊断.cmd'))
assert.ok(nextStep({ hasNet: false, hasKey: true, boot: 'done' }).includes('/clean'))

const idle = idleStatus(
  { hasNet: true, hasKey: true, boot: 'done', previewSize: '1.0 GB', disk: { freeGb: 12, usedPct: 90 } },
  () => 'C 盘空间不足 可用 12.0 GB',
)
assert.ok(idle.includes('可回收约 1.0 GB'))
assert.ok(idle.includes('说确认才删'))

const prompt = buildBootPrompt({
  diagnoseStamp: '[诊断] C 盘可用 12.0 GB',
  previewStamp: '[预览] 可回收约 4.2 GB',
  previewSize: '4.2 GB',
  logPath: 'portable\\logs\\boot-latest.txt',
})
assert.ok(prompt.includes('不要再跑'))
assert.ok(prompt.includes('绝不 -Execute'))
assert.ok(prompt.includes('boot-latest.txt'))
assert.ok(prompt.includes('说确认才删'))

console.log('stamp.test.js ok')
