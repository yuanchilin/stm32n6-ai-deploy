pyocd load .\stm32n647_appli\Debug\Network.hex

# 从 ELF 生成的二进制文件读取向量表前两个 Word（SP 和 PC）
$bin = [System.IO.File]::ReadAllBytes("$(Get-Location)\stm32n647_appli\Debug\Network.bin")
$sp = [System.BitConverter]::ToUInt32($bin, 0)
$pc = [System.BitConverter]::ToUInt32($bin, 4)

pyocd commander -c "halt; wreg sp 0x$('{0:X8}' -f $sp); wreg pc 0x$('{0:X8}' -f $pc); g"