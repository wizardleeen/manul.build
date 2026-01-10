---
title: 安装指南
desc: Manul 安装与快速上手
date: 2026-01-06
---

### 1. 下载并安装 CLI
运行以下命令下载并执行安装脚本：

```bash
curl --proto '=https' --tlsv1.2 -sSf https://manul-lang.org/install.sh | sh
```

### 2. 重载 Shell 配置
使环境变量立即生效（如果您使用的是 Bash，请将 `.zshrc` 替换为 `.bashrc`）：

```bash
source ~/.zshrc
```

### 3. 验证安装
检查版本号以确认安装成功：

```bash
manul --version
```

### 4. 快速开始
创建一个简单的测试项目来验证部署流程：

```bash
mkdir manul-test
cd manul-test
mkdir src

# 创建定义文件
cat << EOF > test.manul
class Product(var name: string)
EOF

# 执行部署
manul deploy
```

**接口测试：**
发送 HTTP 请求以创建一个新的 Product 对象：

```bash
curl -X POST http://localhost:8080/api/product \
  -H "X-App-ID: {app-id}" \
  --data-raw '{name: "鞋子"}'
```