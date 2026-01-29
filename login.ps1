# 检查现有会话并显示缓存时间
$existingContext = Get-AzContext -ErrorAction SilentlyContinue
if ($existingContext) {
    try {
        $token = Get-AzAccessToken
        $expiresAt = $token.ExpiresOn
        $remaining = $expiresAt - (Get-Date)
        Write-Host "✅ 已使用缓存上下文: $($existingContext.Account) ($($existingContext.Subscription))" -ForegroundColor Green
        Write-Host "🔐 缓存有效期至: $($expiresAt.ToString('yyyy-MM-dd HH:mm')) ($([math]::Max(0, $remaining.TotalMinutes)))分钟" -ForegroundColor Cyan
    } catch {
        Write-Host "⚠️  无法获取Token详情（模块版本可能过旧）" -ForegroundColor Yellow
    }
    exit 0
}

# 多任务并发锁机制
$maxRetries = 5
$retryDelay = 2
$lockFile = ".az-login-lock"
$loginSuccess = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    if (-not (Test-Path $lockFile)) {
        New-Item $lockFile -Force | Out-Null
        try {
            Write-Host "ℹ️  正在启动设备认证（请访问 https://microsoft.com/devicelogin）" -ForegroundColor Cyan
            $config = Get-Content vm-config.ini | ConvertFrom-StringData
            Connect-AzAccount -UseDeviceAuthentication -Subscription $config.subscriptionId
            $loginSuccess = $true
        } finally {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
        break
    } else {
        Write-Host "⏳ 检测到其他任务正在登录，等待 $($retryDelay * $i) 秒后重试..." -ForegroundColor Yellow
        Start-Sleep -Seconds ($retryDelay * $i)
    }
}

if (-not $loginSuccess) {
    throw "❌ 无法获取Azure会话（重试超时）"
}

# 显示新登录的缓存时间
try {
    $token = Get-AzAccessToken
    $expiresAt = $token.ExpiresOn
    $remaining = $expiresAt - (Get-Date)
    Write-Host "🔐 设备认证成功！缓存有效期至: $($expiresAt.ToString('yyyy-MM-dd HH:mm')) ($([math]::Max(0, $remaining.TotalMinutes)))分钟" -ForegroundColor Green
} catch {
    Write-Host "⚠️  无法获取Token详情（模块版本可能过旧）" -ForegroundColor Yellow
}