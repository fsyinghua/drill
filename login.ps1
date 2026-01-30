# Check existing session and show cache time
$existingContext = Get-AzContext -ErrorAction SilentlyContinue
if ($existingContext) {
    try {
        $token = Get-AzAccessToken
        $expiresAt = $token.ExpiresOn
        $remaining = $expiresAt - (Get-Date)
        Write-Host "[OK] Using cached context: $($existingContext.Account) ($($existingContext.Subscription))" -ForegroundColor Green
        Write-Host "[TOKEN] Cache valid until: $($expiresAt.ToString('yyyy-MM-dd HH:mm')) ($([math]::Max(0, $remaining.TotalMinutes))) minutes" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN]  Token details unavailable (module version may be outdated)" -ForegroundColor Yellow
    }
    exit 0
}

# Multi-task concurrency lock
$maxRetries = 5
$retryDelay = 2
$lockFile = ".az-login-lock"
$loginSuccess = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    if (-not (Test-Path $lockFile)) {
        New-Item $lockFile -Force | Out-Null
        try {
            Write-Host "ℹ️  Starting device authentication (visit https://microsoft.com/devicelogin)" -ForegroundColor Cyan
            $config = Get-Content vm-config.ini | ConvertFrom-StringData
            Connect-AzAccount -UseDeviceAuthentication -Subscription $config.subscriptionId
            $loginSuccess = $true
        } finally {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
        break
    } else {
        Write-Host "⏳ Another task is logging in. Waiting $($retryDelay * $i) seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds ($retryDelay * $i)
    }
}

if (-not $loginSuccess) {
    throw "❌ Failed to acquire Azure session (timed out)"
}

# Show new login cache time
try {
    $token = Get-AzAccessToken
    $expiresAt = $token.ExpiresOn
    $remaining = $expiresAt - (Get-Date)
    Write-Host "[TOKEN] Device authentication successful! Cache valid until: $($expiresAt.ToString('yyyy-MM-dd HH:mm')) ($([math]::Max(0, $remaining.TotalMinutes))) minutes" -ForegroundColor Green
} catch {
    Write-Host "[WARN]  Token details unavailable (module version may be outdated)" -ForegroundColor Yellow
}