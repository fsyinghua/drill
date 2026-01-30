# 版本发布流程规范

**文档版本**: 1.0  
**生效日期**: 2026-01-30  
**当前版本**: v1.0.0

---

## 1. 版本号规则

采用语义化版本号 (Semantic Versioning):

```
主版本号.次版本号.修订号
   v        X        Y        Z
```

| 版本号类型 | 规则 | 示例 |
|:---------|:----|:----|
| **主版本 (Major)** | 不兼容的变更 | v1.0.0 → v2.0.0 |
| **次版本 (Minor)** | 新功能（向下兼容） | v1.0.0 → v1.1.0 |
| **修订号 (Patch)** | Bug修复（向下兼容） | v1.0.0 → v1.0.1 |

---

## 2. 当前版本状态

| 项目 | 值 |
|:----|:----|
| 当前版本 | **v1.1.0** |
| 发布日期 | 2026-01-30 |
| 状态 | ✅ 已发布 |
| GitHub Release | https://github.com/fsyinghua/drill/releases/tag/v1.1.0 |

---

## 3. 版本历史

### v1.1.0 (2026-01-30) - 并行执行功能

**状态**: ✅ 已发布

**功能**:
- 新增 `-Parallel` 参数，支持批量VM并行执行
- 使用 Start-Job 实现 PowerShell 5.1 兼容的并行处理
- 每个VM独立进程、独立Azure上下文
- 实时状态监控和独立日志文件
- 邮件通知并行发送

**包含文件变更**:
- `drill.ps1` - 添加并行执行模式

### v1.0.0 (2026-01-30) - 初始发布

**状态**: ✅ 已发布

**功能**:
- 单机ASR演练6步自动化脚本
- 批量VM演练支持 (-InputFile)
- 邮件通知功能
- WhatIf预览模式

**测试状态**:
- 单机6步测试: ✅ 通过
- 批量16VM测试: ✅ 通过
- 邮件功能测试: ✅ 通过

**包含文件**:
```
drill.ps1              # 主脚本
test-email-only.ps1    # 邮件测试脚本
vm-config.ini          # VM配置
email-config.ini       # 邮件配置
vms.txt                # 批量VM列表
README.md              # 说明文档
report/*.md            # 测试报告
```

---

## 4. 发布流程

### 4.1 发布前检查清单

- [ ] 所有功能测试通过
- [ ] 代码无语法错误
- [ ] 文档已更新
- [ ] 无敏感信息泄露
- [ ] 本地测试通过

### 4.2 发布步骤

```powershell
# 1. 确认当前分支
git checkout main

# 2. 获取最新代码
git pull origin main

# 3. 创建新Tag (按版本号规则)
git tag -a v1.0.1 -m "Release v1.0.1"

# 4. 推送到GitHub
git push origin v1.0.1

# 5. 在GitHub创建Release
# 访问: https://github.com/fsyinghua/drill/releases/new?tag=v1.0.1
```

### 4.3 GitHub Release 填写内容

```markdown
## What's Changed

- Feature: [新功能描述]
- Fix: [修复内容]
- Docs: [文档更新]

## Test Results

- 单机测试: ✅ 通过
- 批量测试: ✅ 通过
- 邮件测试: ✅ 通过

## Files Changed

- `drill.ps1` - Main script updated
- `test-email-only.ps1` - Email test improved
- `report/*.md` - Reports added
```

---

## 5. 后续版本规划

| 版本 | 计划内容 | 状态 |
|:----|:--------|:----:|
| v1.1.0 | 并行执行模式 (-Parallel) | ✅ 已发布 |
| v1.1.1 | 预期：Bug修复和小改进 | 待开发 |
| v1.2.0 | 预期：日志增强、进度显示 | 待开发 |
| v2.0.0 | 预期：重大功能更新 | 待规划 |

---

## 6. 分支策略

```
main (稳定分支)
    │
    ├── v1.1.0 ──── 已发布 (tag) - 并行执行
    │
    ├── v1.1.1 ──── 下一个版本 (tag)
    │
    └── 开发中代码
```

**原则**:
- 长期分支: 仅 `main`
- 发布标记: 使用 Tag
- 不创建长期 release 分支

---

## 7. 常见问题

### Q: 已发布的Tag可以修改吗?
**A**: ❌ 绝对不可以。已发布Tag是快照，修改会导致历史混乱。

### Q: 如何回滚到旧版本?
```powershell
git checkout v1.0.0
```

### Q: 如何查看所有版本?
```powershell
git tag -l
# 或访问 https://github.com/fsyinghua/drill/releases
```

### Q: 什么时候用 Major vs Minor vs Patch?
- **Patch**: 修复bug、优化代码
- **Minor**: 新功能（不破坏现有功能）
- **Major**: 破坏性变更、API不兼容

---

## 8. 链接

- GitHub Releases: https://github.com/fsyinghua/drill/releases
- 当前版本: v1.1.0
- 下一个版本: v1.1.1

---

*文档更新: 2026-01-30*
*当前版本: v1.1.0*
