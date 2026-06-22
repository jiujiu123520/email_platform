# 推送到 GitHub 指南

## 1. 在 GitHub 上创建新仓库

访问 https://github.com/new 创建一个新仓库：
- 仓库名：`mail-system`
- 描述：自托管邮件系统，支持 SMTP/POP3/IMAP 多端口、SSL 加密、域名绑定
- 可见性：Public（开源）或 Private
- **不要**勾选 "Initialize this repository with a README"（我们已有本地代码）

## 2. 初始化本地仓库

```bash
cd /path/to/mail-system

# 初始化
git init

# 配置 Git 用户（首次使用）
git config user.name  "Your Name"
git config user.email "your.email@example.com"

# 添加 .gitignore
# （项目根目录已有 .gitignore）

# 添加所有文件
git add .

# 首次提交
git commit -m "Initial commit: MailSystem v1.0.0"
```

## 3. 关联远程仓库并推送

```bash
# 添加远程仓库（替换 yourname）
git remote add origin https://github.com/yourname/mail-system.git

# 推送到 main 分支
git branch -M main
git push -u origin main
```

如果使用 SSH：
```bash
git remote add origin git@github.com:yourname/mail-system.git
git push -u origin main
```

## 4. 后续更新

```bash
# 修改文件后
git add .
git commit -m "feat: 添加某某功能"
git push

# 创建新分支
git checkout -b feature/new-feature
git push -u origin feature/new-feature
```

## 5. 添加 Release

推送完成后到 GitHub 仓库页面 → Releases → Draft a new release：
- Tag: `v1.0.0`
- Title: `MailSystem v1.0.0`
- Description: 复制 `CHANGELOG.md` 内容
- 附件：可以上传 `mail-system-v1.0.0.tar.gz`

## 6. 推荐 Git 设置

```bash
# 设置默认编辑器
git config --global core.editor "vim"

# 设置默认分支名
git config --global init.defaultBranch main

# 启用彩色输出
git config --global color.ui auto
```

## 7. 推荐的提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

- `feat: 新增功能`
- `fix: 修复 BUG`
- `docs: 文档更新`
- `style: 代码格式调整`
- `refactor: 重构`
- `test: 测试相关`
- `chore: 构建/工具链更新`

示例：
```bash
git commit -m "feat(api): 添加 API Key 管理接口"
git commit -m "fix(smtp): 修复 STARTTLS 后无法重新协商的问题"
git commit -m "docs: 更新安装文档"
```

## 8. 推送到 Gitee（国内镜像，可选）

```bash
git remote add gitee https://gitee.com/yourname/mail-system.git
git push -u gitee main
```
