# 参与贡献

感谢你帮助改进 C 盘清理助手。

## 反馈问题

请优先使用仓库的 Issue 模板。提交日志或截图前，请隐藏 Windows 用户名、目录中的个人信息、账号标识及其他隐私数据。

## 提交代码

1. 从 `main` 创建分支。
2. 修改后运行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.Tests.ps1
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-portable.ps1
   ```

3. 涉及新清理规则时，必须说明数据用途、删除影响、路径边界和是否默认勾选。
4. 不接受绕过系统权限、直接清理未知系统目录或默认勾选高风险数据的改动。
5. 提交 Pull Request，并描述验证方式。

## 新清理规则要求

每个规则至少应包含：显示名称、路径范围、用途说明、删除影响、删除模式与路径保护测试。任何清理候选都必须默认不勾选。
