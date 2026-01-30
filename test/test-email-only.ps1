<#
.SYNOPSIS
    ASR演练邮件通知测试脚本
.DESCRIPTION
    只测试邮件发送功能，不执行任何Azure ASR指令
    用于验证邮件配置是否正确
.PARAMETER vmName
    要测试的虚拟机名称
.PARAMETER step
    演练步骤 (1-6)
.EXAMPLE
    .\test-email-only.ps1 -vmName CA01SSEGHK -step 1
    测试发送单台VM第1步的邮件
.EXAMPLE
    .\test-email-only.ps1 -vmName CA01SSEGHK -step All
    测试发送单台VM全部6步的邮件
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$vmName,
    [Parameter(Mandatory=$false)]
    [ValidateSet(1,2,3,4,5,6,"All")]
    [string]$step = "All"
)

function Read-Ini {
    param([string]$FilePath)
    (Get-Content $FilePath) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

function Send-DrillEmail {
    param(
        [string]$TargetVm,
        [int]$Step,
        [string]$SmtpServer,
        [int]$Port,
        [PSCredential]$Credential,
        [string]$From,
        [string[]]$To,
        [string]$Body
    )

    $subject = "[DRILL] $TargetVm step $Step"

    try {
        Send-MailMessage `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -UseSsl `
            -Credential $Credential `
            -From $From `
            -To $To `
            -Subject $subject `
            -Body $Body `
            -ErrorAction Stop

        Write-Host "✅ 邮件发送成功: $subject" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ 邮件发送失败: $subject" -ForegroundColor Red
        Write-Host "错误信息: $_" -ForegroundColor Yellow
        return $false
    }
}

# 读取配置
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[EMAIL TEST] 邮件功能测试" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$emailConfig = Read-Ini -FilePath "email-config.ini"

if (-not $emailConfig) {
    Write-Error "无法读取 email-config.ini"
    exit 1
}

Write-Host "[CFG] 邮件配置已加载" -ForegroundColor Cyan
Write-Host "  - SMTP服务器: $($emailConfig.smtpServer)"
Write-Host "  - 端口: $($emailConfig.port)"
Write-Host "  - 发件人: $($emailConfig.username)"
Write-Host "  - 收件人: $($emailConfig.to)"

# 准备凭据
$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

$toList = $emailConfig.to.Split(',')

# 确定测试步骤
$stepsToTest = @()
if ($step -eq "All") {
    $stepsToTest = 1,2,3,4,5,6
} else {
    $stepsToTest = @([int]$step)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[TEST] 开始测试邮件发送" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VM名称: $vmName"
Write-Host "测试步骤: $($stepsToTest -join ', ')"
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($s in $stepsToTest) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $body = @"
ASR演练邮件通知测试

测试信息:
- 虚拟机: $vmName
- 演练步骤: $s
- 测试时间: $timestamp
- 状态: 测试邮件

这是一封测试邮件，用于验证ASR演练脚本的邮件通知功能是否正常。
如果收到此邮件，说明邮件配置正确。
"@

    Write-Host "--- Step $s ---" -ForegroundColor White

    $result = Send-DrillEmail `
        -TargetVm $vmName `
        -Step $s `
        -SmtpServer $emailConfig.smtpServer `
        -Port $emailConfig.port `
        -Credential $cred `
        -From $emailConfig.username `
        -To $toList `
        -Body $body

    if ($result) {
        $successCount++
    } else {
        $failCount++
    }

    Write-Host ""

    # 避免邮件发送过快，添加短暂延迟
    Start-Sleep -Seconds 2
}

# 测试结果汇总
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[RESULT] 测试结果汇总" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "总测试数: $($stepsToTest.Count)"
Write-Host "成功: $successCount" -ForegroundColor Green
Write-Host "失败: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "✅ 所有邮件测试通过！" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ 部分邮件测试失败，请检查邮件配置" -ForegroundColor Red
    exit 1
}
