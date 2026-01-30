# Full build pipeline with automated checks
try {
    Write-Host "[BUILD] Starting validation..." -ForegroundColor Cyan

    # Static code analysis
    Write-Host "[PSRule] Running static analysis..."
    Install-Module PSRule -Force -Scope CurrentUser
    Invoke-PSRule -Path . -ErrorAction Stop

    # Unit tests with coverage
    Write-Host "[Pester] Running test suite..."
    Install-Module Pester -Force -Scope CurrentUser
    $testResult = Invoke-Pester -Path Tests/ -CodeCoverage -PassThru -ErrorAction Stop
    
    if ($testResult.FailedCount -gt 0) {
        throw "${testResult.FailedCount} tests failed"
    }

    Write-Host "[SUCCESS] All checks passed!" -ForegroundColor Green
}
catch {
    Write-Error "[FAILURE] Build interrupted: $_"
    exit 1
}
