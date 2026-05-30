<#
.SYNOPSIS
    STM32N647 AI 模型部署脚本（Development boot 模式烧录）
.DESCRIPTION
    使用 STM32CubeProgrammer CLI 将 AI 推理固件烧录到 STM32N647 内部 Flash。
    
    === 完整部署流程 ===
    1. 运行 .\run.ps1           → 生成 ONNX + 转换为 NPU 微码 (stm32n647_appli/AI/)
    2. 运行 .\build.ps1         → 编译固件，生成 Network.hex
    3. 运行 .\deploy.ps1         → 烧录 Network.hex 到开发板内部 Flash
    
    === 烧录前准备 ===
    1. 将 BOOT1 接 3.3V, BOOT0 任意 → 进入 Development boot 模式
    2. 连接 Type-C 调试线到电脑
    3. 开发板上电
    
    === 烧录后 ===
    断开电源 → BOOT0/BOOT1 都接 GND → 重新上电运行

    === 内存布局（STM32N647 内部 Flash） ===
    0x08000000    AI 推理固件（Network.hex，~2KB）
                 内部 Flash 共 32MB (0x08000000 ~ 0x09FFFFFF)
                 完全足够 AI 推理固件使用

.PARAMETER ModelHexPath
    编译产物的烧录映像路径（默认：stm32n647_appli/Debug/Network.hex）
    支持 .hex 或 .bin 格式
#>

param(
    [string]$ModelHexPath = "$PSScriptRoot\stm32n647_appli\Debug\Network.hex"
)

# ============================================================
# 配置区
# ============================================================
$CUBEPROG = "C:\Users\Yuan\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"

# 检查模型文件
if (-not (Test-Path $ModelHexPath)) {
    Write-Error "固件文件未找到：$ModelHexPath"
    Write-Host ""
    Write-Host "如何生成 Network.hex："
    Write-Host "  1. 运行 .\run.ps1 生成 NPU 微码 (stm32n647_appli/AI/)"
    Write-Host "  2. 运行 .\build.ps1 编译固件"
    Write-Host "  3. 编译产物在 stm32n647_appli/Debug/ 下"
    Write-Host ""
    Write-Host "或者指定其他路径："
    Write-Host "  .\deploy.ps1 -ModelHexPath ""D:\path\to\Network.hex"""
    exit 1
}

Write-Host "========================================"
Write-Host " STM32N647 AI 模型烧录"
Write-Host "========================================"
Write-Host "开发板模式：Development boot（BOOT1接3.3V）"
Write-Host "固件文件：$ModelHexPath"
Write-Host "烧录目标：内部 Flash (0x08000000)"
Write-Host "========================================"
Write-Host ""

# ------------------------------------------
# Step 1: 烧录到内部 Flash
# ------------------------------------------
# 说明：
#   .hex 文件内部已编码地址 0x08000000（内部 Flash 起始地址），
#   STM32CubeProgrammer 解析 .hex 文件时会自动使用内部地址，
#   通过标准 SWD 协议直接写入内部 Flash，无需外部加载器。
#
#   如果使用 .bin 文件，需要显式指定地址参数：
#     STM32_Programmer_CLI.exe -c port=SWD mode=UR -w file.bin 0x08000000 -v
#
#   为什么不用外部加载器 (-el)？
#   - MX25UM25645G 外部加载器用于操作外部 NOR Flash (0x70000000 映射)
#   - AI 推理固件只有 ~2KB，烧录到内部 Flash 0x08000000 即可
#   - 内部 Flash 共 32MB，完全足够
#   - 标准 SWD 协议直接编程内部 Flash，更稳定可靠
Write-Host "[1/2] 正在连接并烧录到内部 Flash (0x08000000)..."

# 判断文件类型，.bin 需要指定地址
$ext = [System.IO.Path]::GetExtension($ModelHexPath).ToLower()
try {
    if ($ext -eq ".bin") {
        & $CUBEPROG -c port=SWD mode=UR `
            -w "$ModelHexPath" 0x08000000 -v 2>&1
    } else {
        & $CUBEPROG -c port=SWD mode=UR `
            -w "$ModelHexPath" -v 2>&1
    }
} catch {
    Write-Host "烧录命令执行异常：$_"
    exit 1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[2/2] 烧录成功！"
    Write-Host ""
    Write-Host "下一步操作："
    Write-Host "  1. 断开开发板电源"
    Write-Host "  2. 将 BOOT0、BOOT1 都接 GND（进入 Flash boot 模式）"
    Write-Host "  3. 重新上电运行"
} else {
    Write-Host ""
    Write-Host ""
    Write-Host "烧录失败，请检查："
    Write-Host "  1. ST-Link 连接是否正确"
    Write-Host "  2. BOOT1 是否已接 3.3V（Development boot 模式）"
    Write-Host "  3. 开发板是否已上电"
    Write-Host "  4. JTAG/SWD 排线连接是否稳定"
    Write-Host ""
    Write-Host "========================================="
    Write-Host " 技术诊断："
    Write-Host "  原因：hex 文件地址 (0x08000000) 与外部加载器"
    Write-Host "        映射区域 (0x70000000) 不匹配"
    Write-Host "  修复：已移除外部加载器，使用标准 SWD 协议直接"
    Write-Host "        烧录到内部 Flash，无需 -el 参数"
    Write-Host "========================================="
}