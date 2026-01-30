# AGENTS.md - PowerShell Project Guidelines

## Build/Lint/Test Commands

### Core Commands
`pwsh -ExecutionPolicy Bypass -File .\build.ps1` - Full build pipeline
`pwsh -Command "Install-Module Pester -Force; Invoke-Pester -Path Tests/"` - Run all tests
`pwsh -Command "Invoke-Pester -Path Tests/login.Tests.ps1"` - Run single test file
`pwsh -Command "Invoke-Pester -Path Tests/ -Filter { $_.Name -like \"*login*\" }"` - Run focused tests
`pwsh -Command "Install-Module PSRule -Force; Invoke-PSRule -Path ."` - Lint code

### Test Execution Tips
1. Debug failing test: `Invoke-Pester -Path Tests/login.Tests.ps1 -Debug`
2. Generate coverage report: `Invoke-Pester -Path Tests/ -CodeCoverage -OutFile coverage.xml`
3. Run tests with custom parameters: `Invoke-Pester -Path Tests/ -TestCases @{Input=1; Expected=2}`

## Code Style Guidelines

### Naming Conventions
- Functions: `Verb-Noun` (approved verbs from `Get-Verb`)
- Variables: `$camelCase` (`$tokenExpiry`, `$maxRetries`)
- Constants: `$UPPER_SNAKE_CASE` (`$MAX_LOGIN_RETRIES = 5`)
- File names: `PascalCase` (LoginScript.ps1)

### Imports
- Use `Import-Module` with explicit version: `Import-Module Az.Accounts -RequiredVersion 2.9.0`
- Group imports by source (Azure modules first, then internal)
- Avoid wildcard imports (`Import-Module *`)

### Formatting Rules
- Indentation: 4 spaces (NO tabs)
- Braces on new lines:
  ```powershell
  if ($condition) {
      Do-Something
  }
  ```
- Line length: Max 120 characters
- Parameter blocks:
  ```powershell
  function Connect-Azure {
      param(
          [string]$SubscriptionId,
          [switch]$UseDeviceAuth
      )
  ```

### Type Guidelines
- Always specify parameter types (`[string]`, `[int]`)
- Use `[ValidateRange()]` for numeric validation
- Prefer `[SecureString]` for sensitive data
- Avoid `[object]` type except for dynamic scenarios

### Error Handling
- Always use `-ErrorAction Stop` with Azure commands
- Structured try/catch:
  ```powershell
  try {
      Connect-AzAccount -UseDeviceAuthentication
  }
  catch {
      Write-Error "[AZURE] Login failed: $_"
      exit 1
  }
  ```
- Validate parameters:
  ```powershell
  param(
      [ValidateNotNullOrEmpty()]
      [string]$ResourceGroup
  )
  ```

### Security Practices
- NEVER hardcode secrets (use `$env:AZURE_CLIENT_SECRET`)
- Sanitize user inputs in device code flows
- Use `[SecureString]` for sensitive parameters
- Always verify token expiration:
  ```powershell
  if ($token.ExpiresOn -lt (Get-Date)) {
      Renew-Token
  }
  ```

### PowerShell 7+ Specifics
- Use `??` null-coalescing operator
- Prefer `ForEach-Object -Parallel` for concurrency
- Use `try/finally` for lock file handling (see login.ps1 pattern)
- Avoid Write-Host in libraries (use Write-Output instead)

## Project-Specific Patterns

### Azure Authentication Flow
1. Check existing context first (`Get-AzContext`)
2. Implement lock file mechanism for concurrent logins
3. Always show token expiry time:
   ```powershell
   Write-Host "[TOKEN] Valid until: $($expiresAt:yyyy-MM-dd HH:mm)"
   ```

### Concurrency Handling
- Use `.az-login-lock` pattern from login.ps1
- Implement exponential backoff:
  ```powershell
  Start-Sleep -Seconds ($retryDelay * $i)
  ```

## Toolchain Configuration

### PSRule Setup
Create `.ps-rule/azure.rules.ps1`:
```powershell
Rule 'UseApprovedVerbs' {
    $targetName -match '^(Get|Set|New|Test|Remove)-'
}
```

### Pester Structure
Tests/login.Tests.ps1 should contain:
```powershell
Describe 'Azure Login' {
    It 'Handles token expiration' {
        $expiresAt = (Get-Date).AddMinutes(-5)
        Check-TokenExpiry $expiresAt | Should -Be $true
    }
}
```

## Pull Request Requirements
1. All scripts must pass PSRule checks
2. New features require corresponding Pester tests
3. Maintain Windows PowerShell 5.1 compatibility
4. Document all public functions with `<# #>` comments

## Additional Rules
- No Cursor-specific rules found (.cursor/rules/ not present)
- No Copilot instructions found (.github/copilot-instructions.md not present)

## Troubleshooting
- CRLF issues: `git config core.autocrlf true`
- Module conflicts: `pwsh -NoProfile -Command ...`
- Debug encoding: `[Console]::OutputEncoding = [Text.Encoding]::UTF8`

## References
- Azure PowerShell Docs: https://learn.microsoft.com/powershell/azure
- Pester Best Practices: https://pester.dev/docs/best-practices
- PSRule Guidelines: https://microsoft.github.io/PSRule/

## ASR Drill Script Usage

### Single VM Execution
```powershell
# Simulation mode
.\drill.ps1 -vmName CA01SSEGHK -step 1 -WhatIf

# Real execution
.\drill.ps1 -vmName CA01SSEGHK -step 1
```

### Batch VM Execution
```powershell
# Create VM list file
"CA01SSEGHK", "DMS15SSEGHK", "DMS16SSEGHK" | Out-File -Encoding utf8 vms.txt

# Simulation mode
.\drill.ps1 -InputFile vms.txt -step 1 -WhatIf

# Real execution (sequential)
.\drill.ps1 -InputFile vms.txt -step 1

# Real execution (parallel - recommended for 10+ VMs)
.\drill.ps1 -InputFile vms.txt -step 1 -Parallel
```

### Parameter Reference
| Parameter | Description | Default |
|-----------|-------------|---------|
| `-vmName` | Single VM name to process | - |
| `-InputFile` | Path to text file with VM names (one per line) | - |
| `-step` | Drill step (1-6) | - |
| `-WhatIf` | Preview mode without execution | - |
| `-Parallel` | Run multiple VMs in parallel (batch mode only) | - |
| `-MaxRetries` | Maximum retry attempts for transient failures | 3 |
| `-RetryDelay` | Delay in seconds between retries | 5 |
| `-Timeout` | Global timeout in seconds (0 = unlimited) | 0 |

### Logging System

The drill script uses a unified logging system with the following format:

```
yyyy-MM-dd HH:mm:ss.fff | [VMName] Module | Action | Command | Status | Error
```

#### Log Fields
| Field | Description | Example |
|-------|-------------|---------|
| Timestamp | ISO 8601 format with milliseconds | 2026-01-30 10:30:45.123 |
| VMName | Target VM name (for batch/parallel) | CA01SSEGHK |
| Module | Functional module | Azure, ASR, Email, Main |
| Action | Specific action performed | SelectSubscription, Failover |
| Command | PowerShell command executed | Start-AzRecoveryServicesAsr... |
| Status | Result status | SUCCESS, FAILED, RETRY, WHATIF, INFO |
| Error | Detailed error message (on failure) | Exception details |

#### Log File Location
- Logs are stored in the `logs/` directory
- File naming: `drill-{step}-{timestamp}.log`
- Summary file: `{logfile}.summary.txt`

#### Example Log Output
```
2026-01-30 10:30:45.123 |  Main | StartDrill | step=1, parallel=True | SUCCESS
2026-01-30 10:30:45.125 | [CA01SSEGHK] Azure | SelectSubscription | subscriptionId=xxx | SUCCESS
2026-01-30 10:30:46.234 | [CA01SSEGHK] ASR | StartFailoverJob | Command: Start-AzRecoveryServicesAsrUnplannedFailoverJob... | RUNNING
2026-01-30 10:32:15.456 | [CA01SSEGHK] ASR | FailoverCompleted |  | SUCCESS
2026-01-30 10:32:16.789 | [CA01SSEGHK] Email | NotificationSent |  | SUCCESS
2026-01-30 10:32:17.012 |  Main | AllCompleted |  | SUCCESS
```

#### Log Modules
| Module | Description |
|--------|-------------|
| Main | Main orchestration logic |
| Config | Configuration loading |
| Azure | Azure subscription/vault operations |
| ASR | Site Recovery operations |
| Email | Email notification operations |
| Parallel | Parallel job management |
| Retry | Retry mechanism events |