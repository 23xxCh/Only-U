import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'only-u-ops-skill'
export const inject = ['skills']

export function apply(ctx) {
  const pkgDir = dirname(fileURLToPath(import.meta.url))
  const content = readFileSync(join(pkgDir, 'skills', 'only-u-ops', 'SKILL.md'), 'utf8')

  // 技能注册表挂载（source: 'runtime'，随会话注入给模型）
  ctx.skills.register({
    name: 'only-u-ops',
    description: 'Only-U USB 运维会话。Windows 上做只读诊断和带误删防护的清理预览；无网用便携脚本。',
    source: 'runtime',
    content,
  })
}
