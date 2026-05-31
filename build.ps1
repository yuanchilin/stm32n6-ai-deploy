<#
.SYNOPSIS
    STM32N647 AI 推理固件编译脚本（CMake 交叉编译）
.DESCRIPTION
    在 stm32n647_appli/ 下执行 CMake 配置 + make 编译，
    生成 Debug/Network.elf，并可选生成 hex/bin 烧录映像。
    
    注意：需要先运行 .\run.ps1 生成 NPU 微码到 stm32n647_appli/AI/。

.PARAMETER BuildDir
    构建目录名称（默认 Debug）

.PARAMETER Clean
    仅清理构建产物，不编译
.PARAMETER Rebuild
    先清理，再重新编译

.PARAMETER GenerateHex
    编译完成后是否生成 network.hex 和 network.bin（默认 $true）

.PARAMETER Jobs
    并行编译线程数（默认自动检测 CPU 核心数）
#>

param(
    [string]$BuildDir = "Debug",
    [switch]$Clean,
    [switch]$Rebuild,
    [switch]$NoHex,
    [int]$Jobs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
)

$ErrorActionPreference = 'Stop'
$RootDir = $PSScriptRoot
$AppDir = Join-Path $RootDir "stm32n647_appli"
$BuildPath = Join-Path $AppDir $BuildDir

Write-Host "========================================"
Write-Host " STM32N647 AI 固件编译"
Write-Host "========================================"
Write-Host "工程目录  : $AppDir"
Write-Host "构建目录  : $BuildPath"
Write-Host "并行线程  : $Jobs"
if ($Clean) { Write-Host "模式      : 仅清理" }
elseif ($Rebuild) { Write-Host "模式      : Rebuild" }
Write-Host "========================================"
Write-Host ""

# 切换到 stm32n647_appli 目录
Push-Location $AppDir
try {
    # ---- Clean / Rebuild ----
    $doClean = $Clean -or $Rebuild
    if ($doClean) {
        Write-Host "[1] 清理旧构建..."
        if (Test-Path $BuildPath) {
            Remove-Item $BuildPath -Recurse -Force
            Write-Host "    已删除 $BuildPath"
        }
        Write-Host "    [OK] 已清理"
        if ($Clean) { return }
        # $Rebuild → 继续往下编译
    }

    # ---- 探测 ninja / make ----
    $generator = "Unix Makefiles"
    $make = "make"
    if (Get-Command ninja -ErrorAction SilentlyContinue) {
        $generator = "Ninja"
        $make = "ninja"
        Write-Host "[0] 检测到 Ninja，使用 Ninja 加速编译"
    } else {
        Write-Host "[0] 使用 Make 编译"
    }

    # ---- CMake 配置 ----
    if (-not (Test-Path (Join-Path $BuildPath "CMakeCache.txt"))) {
        Write-Host "[2] CMake 配置..."
        $toolchain = Resolve-Path "cubeide-gcc.cmake"
        cmake `
            -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
            -S . `
            -B $BuildDir `
            -G"$generator" `
            -DCMAKE_BUILD_TYPE=Debug
        if ($LASTEXITCODE -ne 0) { throw "CMake 配置失败" }
        Write-Host "    OK"
    } else {
        Write-Host "[2] CMake 已配置，跳过"
    }

    # ---- 编译 ----
    Write-Host "[3] 编译..."
    & $make -C $BuildDir -j $Jobs
    if ($LASTEXITCODE -ne 0) { throw "编译失败" }

    $elf = Join-Path $BuildPath "Network.elf"
    if (-not (Test-Path $elf)) { throw "编译产物 $elf 未生成" }

    Write-Host "    → $elf ($((Get-Item $elf).Length) B)"
    Write-Host "    [OK] 编译成功"

    # ---- 生成 hex/bin ----
    if (-not $NoHex) {
        Write-Host "[4] 生成烧录映像..."

        $hex = Join-Path $BuildPath "Network.hex"
        & arm-none-eabi-objcopy -O ihex $elf $hex
        Write-Host "    → $hex ($((Get-Item $hex).Length) B)"

        $bin = Join-Path $BuildPath "Network.bin"
        & arm-none-eabi-objcopy -O binary $elf $bin
        Write-Host "    → $bin ($((Get-Item $bin).Length) B)"

        Write-Host "    [OK] 烧录映像已生成"
        Write-Host ""
        Write-Host "下一步:  .\download.ps1  烧录到开发板"
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================"
Write-Host " 完成"
Write-Host "========================================"