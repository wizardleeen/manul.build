---
title: Installation (Windows)
desc: Getting started with Manul on Windows
date: 2026-01-06
---

### 1. Install via PowerShell
Run the following command in PowerShell to download and install the binary:

```powershell
irm https://manul-lang.org/install.ps1 | iex
```

### 2. Configure Shell
To update your system path and ensure the `manul` command is recognized, you generally need to restart your terminal session.

*Close your current PowerShell window and open a new one.*

### 3. Verify Installation
Confirm that Manul was installed correctly by checking the version:

```powershell
manul --version
```

### 4. Quick Start
Create and deploy a basic "Hello World" project to ensure everything is working.

**Initialize Project:**
```powershell
mkdir manul-test
cd manul-test
mkdir src

# Create a sample file
"class Product(var name: string)" | Set-Content test.manul

# Deploy
manul deploy
```

**Test Endpoint:**
Send a request to the local instance to create a new product using `Invoke-RestMethod`:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/product" `
  -Method Post `
  -Headers @{ "X-App-ID" = "{app-id}" } `
  -Body '{name: "Shoes"}' `
  -ContentType "application/json"
```