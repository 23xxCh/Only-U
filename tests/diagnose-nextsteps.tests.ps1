#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# 用 mock 数据源控制红灯原始数值，断言报告尾部「接下来怎么办」建议行（#17）

BeforeAll {
    $DiagnoseScript = Join-Path $PSScriptRoot '..\portable\diagnose.ps1'

    # 先加载模块，避免 Pester 生成 mock 时解析不到枚举类型（如 PhysicalDiskUsage）
    Import-Module Storage -ErrorAction SilentlyContinue
    Import-Module PrintManagement -ErrorAction SilentlyContinue

    # 真实 Job 对象：mock 代理保留原命令的参数校验（-Job 强制非空，$null 绑定会失败）
    $realJob = Start-Job { 'd17-test-job' }
    Wait-Job -Job $realJob | Out-Null

    # 默认全绿数据；各用例覆盖同名变量后重新执行脚本
    $mockLogicalDisks = @([pscustomobject]@{ DeviceID = 'C:'; Size = 500GB; FreeSpace = 300GB })
    $mockCommittedPercent = 50.0
    $mockWinEvents = @()
    $mockReliability = $null
    $mockPnPDevices = @()

    Mock Get-CimInstance {
        param([string]$ClassName)
        switch ($ClassName) {
            'Win32_LogicalDisk'     { $mockLogicalDisks }
            'Win32_OperatingSystem' { [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 8388608; TotalVirtualMemorySize = 33554432; FreeVirtualMemory = 16777216 } }
            'Win32_PageFileUsage'   { @() }
            'Win32_StartupCommand'  { @() }
            'Win32_PnPEntity'       { $mockPnPDevices }
            default                 { @() }
        }
    }
    Mock Get-Counter { [pscustomobject]@{ CounterSamples = @([pscustomobject]@{ CookedValue = $mockCommittedPercent }) } }
    Mock Get-WinEvent { $mockWinEvents }
    Mock Get-StorageReliabilityCounter { $mockReliability }
    Mock Get-Process { @() }
    Mock Get-Printer { @() }
    Mock Start-Job { $realJob }
    Mock Wait-Job { }
    Mock Stop-Job { }
    Mock Remove-Job { }

    function Invoke-Diagnose {
        & $DiagnoseScript 2>$null | Out-String
    }

    function New-WinEventStub {
        param([int]$Id, [string]$ProviderName)
        [pscustomobject]@{ Id = $Id; ProviderName = $ProviderName; Message = 'test'; TimeCreated = (Get-Date) }
    }
}

Describe 'diagnose 报告尾部「接下来怎么办」' {
    It '全部正常：输出体检通过行，不带固定结尾行' {
        $out = Invoke-Diagnose
        $out | Should -BeLike '*=== 接下来怎么办 ===*'
        $out | Should -BeLike '*系统体检通过，未见红灯。建议 30 天后再查一次。*'
        $out | Should -Not -BeLike '*处理不了？*'
    }

    It 'C 盘剩余 <5%：输出清理建议行' {
        $mockLogicalDisks = @([pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 4GB })
        $out = Invoke-Diagnose
        $out | Should -BeLike '*1. C 盘只剩 4%，亮红灯 → 双击 U 盘里的「清理预览.cmd」，先看清单再按 Y 回收空间*'
        $out | Should -BeLike '*处理不了？带 U 盘去维修店，给师傅看 reports\ 下的 diagnose-*.log。*'
    }

    It '提交内存 >90%：输出内存建议行' {
        $mockCommittedPercent = 92.0
        $out = Invoke-Diagnose
        $out | Should -BeLike '*内存不足（提交内存已用 92%）→ 关掉不用的程序；经常发生建议加内存条*'
    }

    It '事件 2004：输出内存压力建议行' {
        $mockWinEvents = @((New-WinEventStub -Id 2004 -ProviderName 'Microsoft-Windows-Resource-Exhaustion-Detector'))
        $out = Invoke-Diagnose
        $out | Should -BeLike '*系统近期内存压力过高（事件 2004）→ 关掉不用的程序；经常发生建议加内存条*'
    }

    It '7 天内 129/153 ≥3 次：输出备份建议行' {
        $mockWinEvents = @(
            (New-WinEventStub -Id 129 -ProviderName 'storahci'),
            (New-WinEventStub -Id 129 -ProviderName 'storahci'),
            (New-WinEventStub -Id 129 -ProviderName 'storahci')
        )
        $out = Invoke-Diagnose
        $out | Should -BeLike '*硬盘最近 7 天响应慢 3 次 → 尽快备份重要文件，让维修师傅检查 SMART*'
    }

    It 'SMART 异常：输出换盘建议行' {
        $mockReliability = [pscustomobject]@{ ReadErrorsUncorrected = 1; Temperature = 30 }
        $out = Invoke-Diagnose
        $out | Should -BeLike '*硬盘健康告警 → 立即备份重要文件，考虑换盘*'
    }

    It '打印机 CM_PROB 28：输出驱动缺失建议行' {
        $mockPnPDevices = @([pscustomobject]@{ Name = 'TEST-PRINTER'; PNPClass = 'Printer'; ConfigManagerErrorCode = 28 })
        $out = Invoke-Diagnose
        $out | Should -BeLike '*打印机驱动缺失（CM_PROB 28）→ 到打印机厂商官网下载对应型号驱动，或去电脑维修店*'
    }

    It '打印机其他 CM_PROB：输出重装驱动建议行' {
        $mockPnPDevices = @([pscustomobject]@{ Name = 'TEST-PRINTER'; PNPClass = 'Printer'; ConfigManagerErrorCode = 43 })
        $out = Invoke-Diagnose
        $out | Should -BeLike '*打印机驱动异常（CM_PROB 43）→ 先重装该设备驱动再看*'
    }

    It '命中多条：编号逐条列，最多 5 条，超出加溢出提示，结尾固定行' {
        $mockLogicalDisks = @([pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 4GB })
        $mockCommittedPercent = 92.0
        $mockWinEvents = @(
            (New-WinEventStub -Id 2004 -ProviderName 'Microsoft-Windows-Resource-Exhaustion-Detector'),
            (New-WinEventStub -Id 129 -ProviderName 'storahci'),
            (New-WinEventStub -Id 129 -ProviderName 'storahci'),
            (New-WinEventStub -Id 129 -ProviderName 'storahci')
        )
        $mockReliability = [pscustomobject]@{ ReadErrorsUncorrected = 1; Temperature = 30 }
        $mockPnPDevices = @(
            [pscustomobject]@{ Name = 'TEST-PRINTER-A'; PNPClass = 'Printer'; ConfigManagerErrorCode = 28 },
            [pscustomobject]@{ Name = 'TEST-PRINTER-B'; PNPClass = 'Printer'; ConfigManagerErrorCode = 43 }
        )
        $out = Invoke-Diagnose
        $out | Should -Match '(?m)^1\. C 盘只剩 4%'
        $out | Should -Match '(?m)^5\. '
        $out | Should -Not -Match '(?m)^6\. '
        $out | Should -BeLike '*还有 2 条，详见上方红灯清单*'
        $out | Should -BeLike '*处理不了？带 U 盘去维修店，给师傅看 reports\ 下的 diagnose-*.log。*'
    }
}

AfterAll {
    # 清理真实 Job；模块限定调用可绕过 mock
    Microsoft.PowerShell.Core\Remove-Job -Job $realJob -Force -ErrorAction SilentlyContinue
}
