---
title: 安装指南 (Windows)
desc: 在 Windows 上安装与快速上手 Manul
date: 2026-01-06
---

### 1. 下载并安装 CLI
在 PowerShell 中运行以下命令下载并安装二进制文件：

```powershell
irm https://manul-lang.org/install.ps1 | iex
```

### 2. 配置环境
为了更新系统路径并确保 `manul` 命令被正确识别，您通常需要重启终端会话。

*关闭当前的 PowerShell 窗口并重新打开一个新的窗口。*

### 3. 验证安装
检查版本号以确认安装成功：

```powershell
manul --version
```

### 4. 快速开始
创建一个简单的测试项目来验证部署流程。

**初始化项目：**

```powershell
mkdir manul-test
cd manul-test
mkdir src

# 创建定义文件
"class Product(var name: string)" | Set-Content test.manul

# 执行部署
manul deploy
```

**接口测试：**
使用 `Invoke-RestMethod` 发送 HTTP 请求以创建一个新的 Product 对象：

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/product" `
  -Method Post `
  -Headers @{ "X-App-ID" = "{app-id}" } `
  -Body '{name: "鞋子"}' `
  -ContentType "application/json"
```