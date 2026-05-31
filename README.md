# STM32N647 NPU 矩阵乘法 Demo

> 正点原子 STM32N647 核心板 · NPU 矩阵乘法部署方案

利用 ONNX **Gemm** 算子（全连接层）将矩阵乘法伪装为 AI 模型，借助 NPU 硬件加速执行 `C = A × B`。

```raw
输入: input (1, 4)   ← 矩阵 A
         │
         ▼
     [Gemm] ── weights (4, 2)  ← 矩阵 B
               bias (2)        ← 全零偏置
         │
         ▼
输出: output (1, 2)  ← 矩阵 C = A × B
```

---
- [快速开始](#快速开始)
- [构建链总览](#构建链总览)
- [硬件规格](#硬件规格)
- [开发环境](#开发环境)
- [项目结构](#项目结构)
- [软件架构](#软件架构)
- [create_model.py 原理](#create_modelpy-原理)
- [CMake 构建说明](#cmake-构建说明)
- [内存布局](#内存布局)
- [常见问题](#常见问题)

---

## 快速开始

### 1. 生成 ONNX 模型 → 转换 NPU 微码

```powershell
# Windows (PowerShell 7+)
.\run.ps1          # 一键完成：安装依赖 → 生成 ONNX → 调用 stedgeai-core 转 NPU 微码
.\run.ps1 -Clean   # 仅清理旧产物
.\run.ps1 -Rebuild # 先清理再运行
```

```bash
# Linux / WSL
make               # 等效 .\run.ps1
make run CLEAN=1   # 等效 .\run.ps1 -Clean
make run REBUILD=1 # 等效 .\run.ps1 -Rebuild
```

产物自动输出到 `stm32n647_appli/AI/`（`network.h/c`、`network_data.h/c` 等）。

### 2. 编译固件

```powershell
.\build.ps1                      # 一键 CMake 交叉编译
.\build.ps1 -Clean               # 仅清理
.\build.ps1 -Rebuild             # 清理后重新编译
.\build.ps1 -BuildDir Release    # 编译 Release 版
.\build.ps1 -NoHex               # 不自动生成 hex/bin
```

产物：`Debug/Network.elf` + `Debug/Network.hex` + `Debug/Network.bin`

### 3. 下载到开发板并运行

```powershell
.\download.ps1
```

`download.ps1` 自动完成两步：

1. `pyocd load .\stm32n647_appli\Debug\Network.hex` — 通过 SWD 加载到内部 SRAM
2. 从 `Network.bin` 读取向量表前两个 word（SP 和 PC），通过 pyocd commander 设置寄存器并直接运行：

   ```powershell
   $bin = [System.IO.File]::ReadAllBytes("$(Get-Location)\stm32n647_appli\Debug\Network.bin")
   $sp  = [System.BitConverter]::ToUInt32($bin, 0)
   $pc  = [System.BitConverter]::ToUInt32($bin, 4)
   pyocd commander -c "halt; wreg sp 0x$('{0:X8}' -f $sp); wreg pc 0x$('{0:X8}' -f $pc); g"
   ```

> 固件直接运行于内部 RAM，pyocd commander **无需**指定 `--target` 即可读写寄存器。

### 4. 串口查看输出

连接 USART1（PB6 TX / PB7 RX，115200 8N1）即可看到：

- AI 网络初始化状态（成功/失败）
- 每 5000 次循环自动推理，输入 `[1, 2, 3, 4]` 并打印结果
- 用户输入回车回显

---

## 构建链总览

```
                          create_model.py
                               │
                          matrix_mul.onnx
                               │
                    stedgeai-core generate
                               │
                    stm32n647_appli/AI/ (NPU 微码)
                               │
                    CMake 交叉编译
                               │
                    Debug/Network.{elf,hex,bin}
                               │
                    pyocd load → 内部 SRAM
                    pyocd commander → 设置 PC/SP → 运行
```

### 独立分步（不依赖 run.ps1 / build.ps1）

```powershell
# 1. 生成 ONNX 模型
conda activate stm32n6_ai
python create_model.py

# 2. 转换为 NPU 微码
stedgeai-core generate --model matrix_mul.onnx --target stm32n6 --type onnx `
  --output stm32n647_appli/AI --allocate-inputs --allocate-outputs --verbosity 0

# 3. CMake 编译
cd stm32n647_appli
cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake -S . -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
make -C Debug -j
cd ..

# 4. 下载 + 运行
.\download.ps1
```

---

## 硬件规格

| 项目 | 说明 |
|------|------|
| 核心板 | 正点原子 STM32N647 核心板 |
| MCU | STM32N647A0HXQ (Cortex-M55 + Ethos NPU) |
| 外部 Flash | MX25UM25645G（256Mb OctoSPI NOR Flash, 0x70000000） |
| 外部 RAM | 32MB HyperRAM（0x90000000，DEBUG 模式启用） |
| 串口 | USART1, PB6(TX) / PB7(RX), 115200 8N1 |
| 调试接口 | 板载 ST-LINK, Type-C |
| LED | PE10（LED0）、PG10 |

---

## 开发环境

| 项目 | 约定 |
|------|------|
| **操作系统** | Windows 11 / WSL2 (Ubuntu 22.04) |
| **Shell** | PowerShell (pwsh) 7+（首选）, bash（备用） |
| **Python** | 3.12 (Miniconda, 环境名 `stm32n6_ai`) |
| **ARM 工具链** | `arm-none-eabi-gcc` ≥ 14.3 |
| **构建系统** | CMake ≥ 3.20 + Unix Makefiles / Ninja |
| **ST.AI 中间件** | `D:/Downloads/NPU/4.0/Middlewares/ST/AI/` |
| **STM32Cube_FW_N6** | `D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/` |
| **BSP 驱动** | `D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/` |
| **烧录工具** | pyocd（`pip install pyocd`）+ `pyocd pack install stm32n647` |
| **stedgeai-core** | 自动检测 `D:/ST/STEdgeAI/*/` 或 pip 安装 |

### 初始化 conda 环境

```powershell
conda create -n stm32n6_ai python=3.12 -y
conda activate stm32n6_ai
pip install numpy onnx pyocd
pyocd pack install stm32n647
```

---

## 项目结构

```
├── build.ps1                  # CMake 交叉编译脚本
├── run.ps1                    # 一键部署入口（生成 ONNX → 转 NPU 微码）
├── download.ps1               # pyocd 烧录 + 运行脚本
├── create_model.py             # ONNX Gemm 模型生成器
├── Makefile                   # make 入口（代理 run.ps1 / build.ps1）
├── matrix_mul.onnx            # 生成的 ONNX 模型（.gitignore）
│
├── stm32n647_appli/           # STM32N647 固件工程
│   ├── AI/                        # ⚡ NPU 微码（run.ps1 直接输出至此）
│   │   ├── network.h / .c         # 网络 API
│   │   ├── network_data.h / .c    # 权重数据
│   │   ├── network_details.h      # 网络详细信息
│   │   └── stai.h                 # ST.AI 运行时 API
│   ├── Core/                      # STM32CubeMX 核心代码
│   │   ├── Src/
│   │   │   ├── main.c             # ★ 主程序（HAL + AI 推理 + UART 回显 + LED）
│   │   │   ├── stm32n6xx_it.c     # 中断服务
│   │   │   ├── stm32n6xx_hal_msp.c
│   │   │   ├── secure_nsc.c       # 安全非安全调用
│   │   │   └── system_stm32n6xx_s.c
│   │   └── Inc/                   # 头文件
│   ├── Sources/                   # 辅助源文件（syscalls / sysmem）
│   ├── Startup/                   # 汇编启动文件
│   ├── Secure_nsclib/             # 安全非安全库接口
│   ├── Debug/                     # CMake 编译输出
│   │   ├── Network.elf / .hex / .bin
│   │   └── test.map
│   ├── CMakeLists.txt
│   ├── CMakePresets.json
│   ├── cubeide-gcc.cmake          # ARM GCC 工具链文件
│   ├── STM32N647A0HXQ_FLASH.ld   # 链接脚本
│   └── .cproject / .project       # STM32CubeIDE 工程
│
├── st_ai_ws/                 # ST.AI 工作区（可选）
├── .gitignore / .gitattributes
└── README.md
```

---

## 软件架构

### 主程序功能

`main.c` 为 **AI 推理 + UART 回显综合程序**：

- **AI 初始化**：创建网络上下文 → 设置激活/权重缓冲区 → 验证状态
- **定时推理**：每 5000 次循环执行 `stai_network_run()`，输入 `[1.0, 2.0, 3.0, 4.0]`，打印输出
- **UART 回显**：用户输入以回车结束，开发板回显
- **LED 闪烁**：指示系统运行

### HAL 初始化流程

```
SCB_EnableICache() → SCB_EnableDCache() → SystemCoreClockUpdate()
→ HAL_Init() → SystemIsolation_Config()
→ [DEBUG] MX_XSPI1_Init() → HyperRAM_Init() → EnableMemoryMappedMode()
→ MX_USART1_UART_Init() → MX_GPIO_Init()
```

- **Cache**：使能 I-Cache 和 D-Cache
- **系统隔离**：RIF（资源隔离框架），所有外设设为安全特权模式
- **printf**：通过标准 `printf()` 输出到 UART，依赖 `--specs=nano.specs` + `-u,_printf_float`
- **TrustZone**：支持安全/非安全隔离，通过 `secure_nsc.c/h` 实现调用接口

### 中断服务

| 中断 | 文件 | 用途 |
|------|------|------|
| `SysTick_Handler` | `stm32n6xx_it.c` | HAL 时基 |
| `USART1_IRQHandler` | `stm32n6xx_it.c` | UART 接收中断 |

### ST.AI 运行时（stai_\* API）

推理流程：

```c
#include "network.h"
#include "network_data.h"

/* 静态缓冲区 */
static uint8_t ai_network_ctx_buf[STAI_NETWORK_CONTEXT_SIZE]
    __attribute__((aligned(STAI_NETWORK_CONTEXT_ALIGNMENT)));
static uint8_t ai_activations_buf[STAI_NETWORK_ACTIVATIONS_SIZE_BYTES]
    __attribute__((aligned(STAI_NETWORK_ACTIVATION_1_ALIGNMENT)));

/* 初始化 */
stai_network* network = (stai_network*)ai_network_ctx_buf;
stai_network_init(network);

/* 设置激活与权重 */
stai_ptr activations[STAI_NETWORK_ACTIVATIONS_NUM];
activations[0] = (stai_ptr)ai_activations_buf;
stai_network_set_activations(network, activations, STAI_NETWORK_ACTIVATIONS_NUM);

stai_ptr weights[STAI_NETWORK_WEIGHTS_NUM];
weights[0] = (stai_ptr)g_network_weights_array;
stai_network_set_weights(network, weights, STAI_NETWORK_WEIGHTS_NUM);

/* 推理 */
float input_data[STAI_NETWORK_IN_1_SIZE] = {1.0f, 2.0f, 3.0f, 4.0f};
stai_ptr inputs[STAI_NETWORK_IN_NUM], outputs[STAI_NETWORK_OUT_NUM];
stai_network_get_inputs(network, inputs, &n_inputs);
stai_network_get_outputs(network, outputs, &n_outputs);
memcpy(inputs[0], input_data, STAI_NETWORK_IN_1_SIZE_BYTES);
stai_network_run(network, STAI_MODE_SYNC);
float* result = (float*)outputs[0];
printf("输出: [%.6f, %.6f]\r\n", result[0], result[1]);
```

### 外部依赖

| 来源 | 路径 | 内容 |
|------|------|------|
| STM32Cube_FW_N6 HAL | `Drivers/STM32N6xx_HAL_Driver/` | hal_cortex, hal_gpio, hal_uart, hal_xspi 等 |
| CMSIS 设备头文件 | `Drivers/CMSIS/Device/ST/STM32N6xx/Include/` | `stm32n647xx.h`, `partition_stm32n647xx.h` |
| BSP 驱动 | `Drivers/BSP/` | SYS（时钟）、HyperRAM、LED、UART |
| ST.AI 运行时 | `Middlewares/ST/AI/` | 头文件 + `NetworkRuntime1200_CM55_GCC.a` |

> ST.AI 运行时库提供 NPU 加速函数（如 `forward_lite_dense_if32of32wf32`），链接时需包含 `NetworkRuntime1200_CM55_GCC.a`。

---

## create_model.py 原理

```python
from onnx import helper, TensorProto

X = helper.make_tensor_value_info('input', TensorProto.FLOAT, [1, 4])
Y = helper.make_tensor_value_info('output', TensorProto.FLOAT, [1, 2])
W = np.random.randn(4, 2).astype(np.float32)   # 矩阵 B
bias = np.zeros((2,), dtype=np.float32)

node = helper.make_node('Gemm', ['input', 'weights', 'bias'], ['output'],
                        alpha=1.0, beta=1.0, transA=0, transB=0)
```

修改 `[1,4]` / `[1,2]` / `[4,2]` 即可实现任意 `A(m,n) × B(n,p) = C(m,p)` 矩阵乘法。

---

## CMake 构建说明

### 使用 STM32CubeIDE

直接打开 `stm32n647_appli/` 工程（已含 `.cproject` / `.project`）。

### 使用命令行

`build.ps1` 自动探测 Ninja / Make，优先使用 Ninja 加速。

```powershell
cd stm32n647_appli
cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake -S . -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
make -C Debug -j
```

### CMakeLists.txt 关键配置

| 配置项 | 值 |
|--------|-----|
| CPU | `-mcpu=cortex-m55` |
| FPU | `-mfpu=fpv5-d16`（双精度） |
| ABI | `-mfloat-abi=hard` |
| TrustZone | `-mcmse` |
| 运行时 | `--specs=nano.specs` + `--specs=nosys.specs` |
| 链接优化 | `--gc-sections`, `-u,_printf_float` |
| ST.AI 库 | `NetworkRuntime1200_CM55_GCC.a` |
| HAL 驱动 | 直接包含源文件路径（绝对路径） |
| BSP 驱动 | 直接包含源文件路径（绝对路径） |

### 常见链接错误

| 错误 | 原因 | 修复 |
|------|------|------|
| `undefined reference to forward_lite_dense_if32of32wf32` | 缺少 ST.AI 运行时库 | 确认 `NetworkRuntime1200_CM55_GCC.a` 正确链接 |
| `unrecognized option '--major-image-version'` | 链接器路径错误（MSYS2 LD 冲突） | 修正 `cubeide-gcc.cmake` 中 `CMAKE_LINKER` |
| `undefined reference to _printf_float` | 未启用浮点打印 | 添加 `-Wl,-u,_printf_float` 链接标志 |
| `undefined reference to __DSB` | 使用了 CMSIS 函数 | 改用内联汇编 `__asm volatile("dsb")` |

---

## 内存布局

### 内部 RAM（0x34000400 ~ 0x34080000，约 2047KB）

程序加载到内部 RAM 中运行（非 XIP）。地址区间来自 `STM32N647A0HXQ_FLASH.ld`：

| 段 | 起始地址 | 内容 |
|----|---------|------|
| `.isr_vector` | 0x34000400 | 中断向量表 |
| `.text` | 紧接其后 | 代码 + 运行时库 |
| `.rodata` | 紧接其后 | 只读数据（权重等） |
| `.ARM.extab / .ARM` | 紧接其后 | 异常处理表 |
| `.preinit_array / .init_array / .fini_array` | — | 构造/析构函数表 |
| `.data` | — | 初始化全局变量 |
| `.gnu.sgstubs` | — | Secure Gateway 存根 |
| `.bss` | — | 未初始化全局变量 |
| `._user_heap_stack` | — | 堆（0x200）+ 栈（0x800） |

> 各段精确偏移量见 `Debug/test.map`。

### 外部 HyperRAM（0x90000000，32MB）

DEBUG 模式下通过 XSPI1 初始化，映射到 0x90000000，用于调试数据存储。

### 外部 NOR Flash（0x70000000，MX25UM25645G）

通过 OSPI 接口映射，当前固件未使用（所有代码加载到内部 SRAM 运行）。

---

## 常见问题

**pyocd 无法识别目标芯片**

```powershell
pyocd pack find stm32n647    # 搜索目标包
pyocd pack install stm32n647 # 安装
```

**烧录后程序不运行**

检查 `download.ps1` 中的 PC/SP 地址是否与链接脚本匹配。在 `test.map` 中查找：

```powershell
Select-String "Reset_Handler" .\stm32n647_appli\Debug\test.map
Select-String "_estack" .\stm32n647_appli\Debug\test.map
```

**串口无输出**

检查：波特率 115200、8N1、USART1 使用 PB6(TX)/PB7(RX)。

**CMake 配置失败**

确保 ARM GCC 工具链在 PATH 中：

```powershell
$env:PATH = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.3 rel1\bin;$env:PATH"
```

**`build.ps1` 找不到 `cubeide-gcc.cmake`**

确保在项目根目录执行 `.\build.ps1`，脚本会自动切换到 `stm32n647_appli/`。

**编译报错 HAL 头文件找不到**

确认 `stm32n6xx_hal_conf.h` 中开启的外设模块与 `CMakeLists.txt` 中包含的源文件一致。头文件路径在 `cubeide-gcc.cmake` 中配置。

---

> **版本**: 3.0.0（AI 推理 + stai_\* API）  
> **适用平台**: 正点原子 STM32N647 核心板  
> **仓库**: [https://github.com/yuanchilin/stm32n6-ai-deploy](https://github.com/yuanchilin/stm32n6-ai-deploy)