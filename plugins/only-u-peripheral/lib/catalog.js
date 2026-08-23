import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const pkgDir = dirname(fileURLToPath(import.meta.url))

/**
 * 知识库条目 → 运行期目录条目。
 * - exe 一律从插件包内 tools\ 解析（工具随包分发，不依赖外部安装）。
 * - schedulable = 未显式关闭 && 已验证 && 文件真实存在（fail-closed）。
 */
export function loadCatalog(knowledge) {
  return knowledge.map((entry) => {
    const resolved = join(pkgDir, '..', entry.exe)
    const found = existsSync(resolved)

    let reason = null
    if (!found) reason = '工具文件不存在（未随包分发）'
    else if (entry.verified !== true) reason = 'CLI 能力未验证（收录前需逐条实测）'
    else if (entry.schedulable === false) reason = '未开放调度'

    return {
      ...entry,
      exePath: resolved,
      schedulable: entry.schedulable !== false && entry.verified === true && found,
      unschedulableReason: reason,
    }
  })
}
