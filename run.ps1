# STM32N6 NPU 一键部署
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

Write-Host "[1] 依赖"
exec "pip install numpy onnx -q"

Write-Host "[2] 生成 ONNX"
exec "python create_model.py"

Write-Host "[3] 转换 NPU"
$ProgressPreference='SilentlyContinue'
rm npu_model -Recurse -Force -ErrorAction Ignore
$ProgressPreference='Continue'
$exe = @(Get-ChildItem "D:\ST\STEdgeAI\*\Utilities\windows\stedgeai.exe" -ErrorAction Ignore)[-1]
if ($exe) { & $exe generate --model matrix_mul.onnx --target stm32n6 --type onnx --output ./npu_model --allocate-inputs --allocate-outputs --verbosity 0 *>$null }
else { exec "stedgeai-core generate microcode -m matrix_mul.onnx -t STM32N6 -o ./npu_model" }
if (!(Test-Path npu_model/network.h)) { throw "失败" }

Write-Host "[4] 规格"
$h = Get-Content npu_model/network.h -Raw
"  输入 $((($h-split'IN_1_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"
"  权重 $((($h-split'WEIGHTS_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"
"  输出 $((($h-split'OUT_1_SIZE_BYTES\s+\(')[-1]-split'\)')[0])B"

Write-Host "===== 完成 ====="