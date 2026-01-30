# Azure ASR Drill Six-Step Process

| Step | Operation | Direction | Command |
|------|-----------|-----------|---------|
| 1 | Failover | Primary→Recovery | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery` |
| 2 | Commit Failover | - | `Start-AzRecoveryServicesAsrCommitFailoverJob` |
| 3 | Reprotect (Reverse) | - | `Start-AzRecoveryServicesAsrReprotectJob` |
| 4 | Failback | Recovery→Primary | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary` |
| 5 | Commit Failback | - | `Start-AzRecoveryServicesAsrCommitFailoverJob` |
| 6 | Reprotect (Forward) | - | `Start-AzRecoveryServicesAsrReprotectJob` |

## Quick Commands
```powershell
# Single VM
.\drill.ps1 -vmName CA01SSEGHK -step 1
.\drill.ps1 -vmName CA01SSEGHK -step 1 -WhatIf

# Batch execution
.\drill.ps1 -InputFile vms.txt -step 1
.\drill.ps1 -InputFile vms.txt -step 1 -WhatIf
```

## See Also
- Full guide: [ASR_Drill_Guide.md](ASR_Drill_Guide.md)
