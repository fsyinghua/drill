# Azure 灾难恢复演练工具

## 项目概述
提供基于PowerShell的Azure站点恢复(ASR)自动化演练工具，支持：
- 设备认证免密登录
- 6步标准化灾备演练流程
- QQ邮箱自动通知
- **批量VM并行执行** (推荐10+ VM使用)

## 快速开始
### 1. 前置条件
```powershell
# 安装必要模块（首次执行）
Install-Module -Name Az.RecoveryServices -Scope CurrentUser
```

### 2. 配置文件
| 文件                | 说明                     |
|---------------------|--------------------------|
| `vm-config.ini`     | 虚拟机灾备参数           |
| `email-config.ini`  | QQ邮箱SMTP配置           |

### 3. 执行流程
```powershell
# 1. 认证登录
.\login.ps1

# 2. 执行演练（示例）
.\drill.ps1 <虚拟机名> <步骤>
# 例如：.\drill.ps1 pc1 1
```

## 执行模式

### 单机执行
```powershell
# 模拟预览
.\drill.ps1 -vmName CA01SSEGHK -step 1 -WhatIf

# 真实执行
.\drill.ps1 -vmName CA01SSEGHK -step 1
```

### 批量执行（顺序）
```powershell
# 模拟预览
.\drill.ps1 -InputFile vms.txt -step 1 -WhatIf

# 真实执行
.\drill.ps1 -InputFile vms.txt -step 1
```

### 批量执行（并行）- 推荐10+ VM
```powershell
# 模拟预览
.\drill.ps1 -InputFile vms.txt -step 1 -Parallel -WhatIf

# 真实执行
.\drill.ps1 -InputFile vms.txt -step 1 -Parallel
```

## 关键特性
设备认证自动缓存上下文
步骤化操作（1-6步严格流程）
企业级邮件通知
**批量VM并行执行**

> 完整操作文档见 [ASR_Drill_Guide.md](ASR_Drill_Guide.md)
