Describe '2-VM Disaster Recovery Simulation' {
    $testServers = @('CA01SSEGHK', 'DMS15SSEGHK')
    $steps = 1..6

    BeforeAll {
        # 验证核心脚本存在
        $drillPath = Join-Path $PSScriptRoot '..\drill.ps1'
        $true | Should -Be (Test-Path $drillPath)
    }

    It 'Shows correct WhatIf output format for <server> step <step>' -TestCases @(
        foreach ($server in $testServers) {
            foreach ($step in $steps) {
                @{server=$server; step=$step}
            }
        }
    ) {
        param($server, $step)

        $output = & $drillPath $server $step -WhatIf 2>&1

        # 验证模拟标识
        $output -match '\[模拟\]' | Should -Be $true

        # 验证关键命令存在
        $cmdlets = @(
            'Start-AzRecoveryServicesAsrUnplannedFailoverJob',
            'Start-AzRecoveryServicesAsrCommitFailoverJob',
            'Start-AzRecoveryServicesAsrReprotectJob'
        )[$step % 3]
        
        $output -match $cmdlets | Should -Be $true

        # 验证邮件模拟输出
        $output -match 'Send-MailMessage' | Should -Be $true
    }

    It 'Completes full cycle without errors' {
        foreach ($server in $testServers) {
            foreach ($step in $steps) {
                $output = & $drillPath $server $step -WhatIf
                $LASTEXITCODE | Should -Be 0
            }
        }
    }
}