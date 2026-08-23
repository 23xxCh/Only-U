/**
 * 审批门：向 dsh 审批服务请求用户确认（dsh-TUI 弹确认条）。
 * - 无审批服务 → fail-closed，返回 tool-denied/unavailable
 * - 仅 'allowed-once' 放行，其余一律返回 tool-denied
 * - 返回 null 表示允许执行
 */
export async function requestApproval(ctx, exec, toolName, reason) {
  const approval = ctx.get('approval')
  if (!approval) {
    return { kind: 'tool-denied', outcome: 'unavailable', message: '当前环境没有审批服务，无法确认执行' }
  }
  const outcome = await approval.request({
    agent: exec.agent,
    toolName,
    callId: exec.callId,
    reason,
    signal: exec.signal,
  })
  if (outcome !== 'allowed-once') {
    return { kind: 'tool-denied', outcome, message: `用户未批准执行 ${toolName}` }
  }
  return null
}
