# GitHub 上传指南

本仓库已完成本地 `git init` 与首次提交，并通过 `.gitignore` 排除了大文件（如 `data/liaochu.RData`）与运行产物（如 `outputs/`）。

## 1) 在 GitHub 创建仓库

在 `https://github.com/Wanzhe-Liao` 下创建一个新的仓库（建议命名为 `insert-pin-strategy` 或你喜欢的名称；是否 Private 由你决定）。

## 2) 添加远程并推送

将下面的 `<REPO_NAME>` 替换为你创建的仓库名：

```bash
git remote add origin git@github.com:Wanzhe-Liao/<REPO_NAME>.git
git push -u origin main
```

如果提示远程已存在：

```bash
git remote -v
git remote set-url origin git@github.com:Wanzhe-Liao/<REPO_NAME>.git
git push -u origin main
```

## 3) 如需上传大数据（可选）

默认不会把 `data/liaochu.RData` 推到 GitHub（体积过大）。如确实要上传，请考虑 Git LFS，或改为在云盘/对象存储提供下载链接。

