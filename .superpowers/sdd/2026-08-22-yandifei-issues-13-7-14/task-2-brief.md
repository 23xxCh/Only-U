### Task 2: Issue #7 — Driver and printer diagnosis

**Files:**
- Modify: `portable/diagnose.ps1`
- Modify: `portable/tests/diagnose.Tests.ps1`

**Requirements (exact)**

1. Keep the existing `Get-Printer` report and add `Get-Service Spooler` evidence: `Stopped` must say the print service is not running and that this is a software problem, not a missing driver.
2. Add the following `ConfigManagerErrorCode` translations in the script: 1=未配置, 10=无法启动, 22=已被禁用, 28=驱动未安装, 29=电源不足被禁用, 37/39=驱动加载失败, 43=设备自报故障, 45=设备已拔除, 48=被策略阻止, 52=驱动未签名.
3. A translated PnP line must include device, class, error code, Chinese translation, and a practical suggestion. Example: `设备名 [类] 错误码28（驱动未安装）→ 建议：去厂商官网或 Windows Update 可选更新找驱动`.
4. Put recognized device errors in capped buckets (maximum five entries per bucket, with bucket count): missing-driver codes 1/28/37/39/48/52 → official vendor site/Windows Update optional updates; suspected-hardware codes 10/43 → reseat, change port, repair; disabled codes 22/29 → use Device Manager to enable.
5. For the missing-driver bucket only, read `DEVPKEY_Device_HardwareIds` using `Get-PnpDeviceProperty -InstanceId`; use the first entry and emit only a `VEN_xxxx&DEV_xxxx` or `VID_xxxx&PID_xxxx` summary if readable. Silently skip if unavailable.
6. Add `Win32_Printer.DetectedErrorState` evidence: 8=卡纸, 9=脱机, 2/4=无纸, 3/5=缺粉. State these are device/consumable evidence, not driver evidence.
7. Add a port hint: WSD offline → network/WSD protocol likely; TCP/IP → ping can verify; USB → inspect PnP state. Each printer gets a conclusion distinguishing service/driver vs connection/consumable evidence. A nonempty driver name may support a `驱动已装` conclusion, but do not overclaim.
8. Retain the exact normal-machine output `未发现驱动状态异常的即插即用设备` and do not misreport a healthy machine.
9. Add controlled Pester coverage for the mapping and an output format with Chinese translation; keep Pester 3.4/Windows PowerShell 5.1 compatibility. Tests must not depend on actual device state.
10. All diagnostic code remains read-only: no `Enable-PnpDevice`, `Disable-PnpDevice`, driver installation, `pnputil` writes, service changes, device changes, or printer changes. Preserve UTF-8 BOM and existing 8-second/20,000-file directory cap. The complete diagnosis must remain within 60 seconds.
11. Branch is `feat/7-driver-code-translate`; the controller opens a PR to `main` with `Closes #7` as the first body line.
