<#
.SYNOPSIS
    STM32N6 NPU 一键部署
.DESCRIPTION
    从 Python 生成 ONNX → 调用 stedgeai 转换 NPU 微码 → 生成烧录映像。
    
    需要先执行 .\download.ps1 的依赖准备。

.PARAMETER Clean
    仅清理所有旧产物（ONNX、AI/、logs、st_ai_ws），不运行
.PARAMETER Rebuild
    先清理，再重新运行完整流程
.PARAMETER NoHex
    跳过 network.hex / network.bin 生成
#>

param(
    [switch]$Clean,
    [switch]$Rebuild,
    [switch]$NoHex
)

$ErrorActionPreference='Stop'; cd $PSScriptRoot

# conda 环境中执行命令（通过临时 bat，绕过 conda run & pwsh 的流问题）
function exec($c) {
    $f = [IO.Path]::GetTempFileName() -replace '\.tmp$','.bat'
    "@echo off`r`ncall conda activate stm32n6_ai`r`n$c 2>&1" | Set-Content $f -Encoding OEM
    $r = cmd /d /q /c $f
    rm $f -Force
    if ($LASTEXITCODE) { throw "exit=$($LASTEXITCODE): $c" }
    $r
}

Write-Host "===== STM32N6 NPU (1×4→1×2) ====="

# ---- Clean / Rebuild ----
$doClean = $Clean -or $Rebuild
if ($doClean) {
    Write-Host "  [CLEAN] 清理旧产物..."
    Remove-Item matrix_mul.onnx -Force -ErrorAction Ignore
    Remove-Item stm32n647_appli/AI -Recurse -Force -ErrorAction Ignore
    Remove-Item stm32n647_appli/ai -Recurse -Force -ErrorAction Ignore
    Remove-Item logs -Recurse -Force -ErrorAction Ignore
    Remove-Item st_ai_ws -Recurse -Force -ErrorAction Ignore
    Write-Host "     [OK] 已清理"
    if ($Clean) { exit 0 }
    # $Rebuild → 继续往下走
}

Write-Host "[1] 依赖"
exec "pip install numpy onnx -q"

Write-Host "[2] 生成 ONNX"
exec "python create_model.py"

Write-Host "[3] 转换 NPU → stm32n647_appli/AI/"
$ProgressPreference='SilentlyContinue'
Remove-Item stm32n647_appli/AI/* -Recurse -Force -ErrorAction Ignore
$ProgressPreference='Continue'
$outDir = "./stm32n647_appli/AI"
$exe = @(Get-ChildItem "D:\ST\STEdgeAI\*\Utilities\windows\stedgeai.exe" -ErrorAction Ignore)[-1]
if ($exe) { & $exe generate --model matrix_mul.onnx --target stm32n6 --type onnx --output $outDir --allocate-inputs --allocate-outputs --verbosity 0 *>$null }
else { exec "stedgeai-core generate microcode -m matrix_mul.onnx -t STM32N6 -o $outDir" }
if (!(Test-Path stm32n647_appli/AI/network.h)) { throw "转换失败" }

Write-Host "[4] 规格"
$h = Get-Content stm32n647_appli/AI/network.h -Raw
"  输入 $((($h-split'IN_1_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"
"  权重 $((($h-split'WEIGHTS_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"
"  输出 $((($h-split'OUT_1_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"

Write-Host "[5] 生成 network.hex + network.bin"
$elf = "st_ai_ws/build_rt_network/network.elf"
if (Test-Path $elf) {
    $hex = "st_ai_ws/build_rt_network/network.hex"
    $bin = "st_ai_ws/build_rt_network/network.bin"
    & arm-none-eabi-objcopy -O ihex $elf $hex
    Write-Host "  → $hex ($((Get-Item $hex).Length)B)"
    & arm-none-eabi-objcopy -O binary $elf $bin
    Write-Host "  → $bin ($((Get-Item $bin).Length)B)"
    Write-Host ""
    Write-Host "  download.ps1 将自动使用 .bin 格式写入外部 Flash (0x70000000)"
} else {
    Write-Warning "  $elf 不存在，跳过 hex/bin 生成"
    Write-Warning "  请用 STM32CubeIDE 编译 stm32n647_appli/ 后复制 network.hex"
}

Write-Host "===== 完成 ====="