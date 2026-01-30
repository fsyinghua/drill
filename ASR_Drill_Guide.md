# Azure ASR Disaster Recovery Drill Script User Guide

## 1. Quick Start
```powershell
# 1. Device login authentication
.\login.ps1

# 2. Execute drill (example: step 1 for CA01SSEGHK)
.\drill.ps1 -vmName CA01SSEGHK -step 1
```

## 2. Configuration Files

### 2.1 VM Configuration (`vm-config.ini`)
```ini
subscriptionId=your-subscription-id
resourceGroup=RGP-GIT-S-ASR-R-SEA-002
vaultName=RSV-GIT-S-ASR-R-SEA-001
fabricName=asr-a2a-default-eastasia
containerName=asr-a2a-default-eastasia-container
```

### 2.2 Email Configuration (`email-config.ini`)
```ini
smtpServer=smtp.qq.com
port=587
username=your@qq.com
password=email-authorization-code
to=admin1@qq.com,admin2@qq.com
```

## 3. Execution Modes

### 3.1 Single VM Execution
```powershell
# Real execution
.\drill.ps1 -vmName CA01SSEGHK -step 1

# Simulation mode (preview only)
.\drill.ps1 -vmName CA01SSEGHK -step 1 -WhatIf
```

### 3.2 Batch Execution (Multiple VMs)
Create a text file with VM names (one per line):
```text
CA01SSEGHK
DMS15SSEGHK
DMS16SSEGHK
DMSP06UATDHHK
GLD02SSDHHK
GLD02SSEGHK
GLDAPP01VMP
GSDAPP01VMP
GSDAPP02VMT
GSDCSADB01VMP
INFGAL01VMP
INFMID02VMP
INFFPS01VMP
UNF01VMP
UNF02VMP
UNF03VMP
```

Execute batch:
```powershell
# Simulation mode (preview)
.\drill.ps1 -InputFile vms.txt -step 1 -WhatIf

# Real execution
.\drill.ps1 -InputFile vms.txt -step 1
```

### 3.3 Mode Comparison
| Operation | Real Execution | Simulation (-WhatIf) |
|-----------|----------------|----------------------|
| VM Shutdown | Yes | Preview only |
| ASR Status Change | Yes | No |
| Email Notification | Yes | Preview only |
| Output | Azure native job output | Yellow [WHATIF] prefix |

## 4. Safety Operation Process

### 4.1 Mandatory Steps Before Real Execution
```powershell
# Step 1: Generate command snapshot (email record)
.\drill.ps1 -vmName CA01SSEGHK -step 1 -WhatIf > drill-plan.txt

# Step 2: Execute only after confirmation
.\drill.ps1 -vmName CA01SSEGHK -step 1
```

### 4.2 Verification During Execution
- Wait for `State : Completed` (not `InProgress`)
- Check Azure portal: `Vault → Jobs → Recent Jobs`

## 5. Step-by-Step Details
| Step | Operation | Command |
|------|-----------|---------|
| 1 | Failover (Primary→Recovery) | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery` |
| 2 | Commit Failover | `Start-AzRecoveryServicesAsrCommitFailoverJob` |
| 3 | Reprotect (Reverse) | `Start-AzRecoveryServicesAsrReprotectJob` |
| 4 | Failback (Recovery→Primary) | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary` |
| 5 | Commit Failback | `Start-AzRecoveryServicesAsrCommitFailoverJob` |
| 6 | Reprotect (Forward) | `Start-AzRecoveryServicesAsrReprotectJob` |

## 6. Complete Drill Example
```powershell
# 1. Login
.\login.ps1

# 2. Execute failover (step 1)
.\drill.ps1 -vmName CA01SSEGHK -step 1

# 3. Check job status
Get-AzRecoveryServicesAsrJob | Where-Object Operation -eq 'Failover'

# 4. Commit failover (step 2)
.\drill.ps1 -vmName CA01SSEGHK -step 2

# 5. Failback (step 4)
.\drill.ps1 -vmName CA01SSEGHK -step 4

# 6. Complete full cycle (step 5+6)
.\drill.ps1 -vmName CA01SSEGHK -step 5
.\drill.ps1 -vmName CA01SSEGHK -step 6
```

## 7. Batch Drill Example
```powershell
# 1. Create VM list file
"CA01SSEGHK", "DMS15SSEGHK", "DMS16SSEGHK" | Out-File -Encoding utf8 vms.txt

# 2. Preview all VMs
.\drill.ps1 -InputFile vms.txt -step 1 -WhatIf

# 3. Execute for all VMs
.\drill.ps1 -InputFile vms.txt -step 1
```

## 8. Troubleshooting

### 8.1 Common Errors

**"Vault Settings are missing"**
- Run: `Import-AzRecoveryServicesAsrVaultSettingsFile` manually
- Script auto-handles this via `Get-AzRecoveryServicesVaultSettingsFile`

**"VM not found"**
- Verify VM name exists in ASR protected items
- Check `fabricName` and `containerName` in `vm-config.ini`

**"No vault context selected"**
- Ensure `Select-AzSubscription` executed first
- Check subscription ID in config

### 8.2 Log Investigation
```powershell
# Check failover jobs
Get-AzRecoveryServicesAsrJob | Where-Object {$_.Operation -match 'Failover'}

# Check protected items
Get-AzRecoveryServicesAsrReplicationProtectedItem

# Check fabric and container
Get-AzRecoveryServicesAsrFabric
Get-AzRecoveryServicesAsrProtectionContainer
```

## 9. Audit Requirements
- Always preserve `-WhatIf` output before real operations
- Execute during business off-peak hours
- Notify relevant parties in advance
