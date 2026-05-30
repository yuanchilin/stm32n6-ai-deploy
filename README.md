# STM32N647 NPU 矩阵乘法 Demo

> 正点原子 STM32N647 核心板 · NPU 矩阵乘法部署方案

利用 ONNX **Gemm** 算子（全连接层）将矩阵乘法伪装成 AI 模型，让 NPU 硬件加速执行 `C = A × B`。

```
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

## 快速开始

### 一键生成（ONNX 模型 → NPU 微码）

```powershell
# Windows (PowerShell 7+)
.\run.ps1          # 直接运行
.\run.ps1 -Clean   # 仅清理旧产物，不运行
.\run.ps1 -Rebuild # 先清理，再重新运行
```

```bash
# Linux / WSL
make               # 直接运行（等效 .\run.ps1）
make run CLEAN=1   # 仅清理（等效 .\run.ps1 -Clean）
make run REBUILD=1 # 清理后重新运行（等效 .\run.ps1 -Rebuild）
```

自动完成：安装依赖 → 生成 `matrix_mul.onnx` → 调用 `stedgeai-core` 转换为 NPU 微码 → 显示模型规格。

### 编译固件（CMake 交叉编译）

一键编译（推荐）：

```powershell
.\build.ps1
```

等效的手动分步编译：

```powershell
cd stm32n647_appli
cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake -S . -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
make -C Debug -j
```

`build.ps1` 还支持 clean / rebuild、Release 模式、指定线程数等选项：

```powershell
.\build.ps1 -Clean             # 仅清理构建产物，不编译
.\build.ps1 -Rebuild           # 先清理，再重新编译
.\build.ps1 -BuildDir Release  # 编译 Release 版
.\build.ps1 -NoHex             # 编译后不自动生成烧录映像
```

编译产物：`Debug/Network.elf` + `Debug/Network.hex` + `Debug/Network.bin`

### 烧录到开发板

**前提**：开发板设为 **Development boot 模式**（BOOT1 接 3.3V）

```powershell
.\deploy.ps1
```

### 运行
1. 断开电源，BOOT0/GND、BOOT1/GND（Flash boot 模式），重新上电
2. 连接串口（USART1, PB6(TX)/PB7(RX), 115200, 8N1）

---

## 项目结构

```
├── build.ps1               # ★ CMake 交叉编译脚本（编译固件 + 生成烧录映像）
├── run.ps1                 # ★ 一键部署入口（生成 ONNX → 转换 NPU 微码）
├── deploy.ps1              # 烧录脚本（烧录 network.hex 到内部 Flash）
├── create_model.py         # ONNX 模型生成脚本（~30 行）
├── Makefile                # make 入口（代理 run.ps1 / build.ps1）
├── matrix_mul.onnx         # 生成的 ONNX 模型（.gitignore）
├── stm32n647_appli/        # STM32N647 应用程序工程
│   ├── AI/                     # ⚡ NPU 微码输出（run.ps1 直接生成到此目录）
│   │   ├── network.h/c         # 网络 API（输入/输出维度、权重尺寸等）
│   │   ├── network_data.h/c    # 网络权重数据（Gemm 的 W 和 bias）
│   │   ├── network_details.h   # 网络详细信息
│   │   ├── stai.h              # ST.AI 运行时 API 头文件
│   │   └── ...
│   ├── Sources/               # 裸机源文件（无 HAL 依赖）
│   │   ├── main.c              # ★ 主程序：初始化 + AI 推理 + printf 输出
│   │   ├── syscalls.c          # 系统调用（_sbrk 等）
│   │   └── sysmem.c            # 系统内存管理（堆区定义）
│   ├── Startup/                # 启动文件
│   │   └── startup_stm32n647a0hxq.s  # 汇编启动文件（Reset_Handler, 中断向量表）
│   ├── Debug/                  # CMake 编译输出
│   │   ├── Network.elf         # 最终固件
│   │   └── test.map            # 链接映射表
│   ├── CMakeLists.txt          # CMake 构建配置
│   ├── CMakePresets.json       # CMake 预设（CubeIDE 集成）
│   ├── cubeide-gcc.cmake       # ARM GCC 工具链文件
│   ├── STM32N647A0HXQ_FLASH.ld # 链接脚本（内部 Flash 布局）
│   ├── .cproject / .project    # STM32CubeIDE 工程文件
│   └── .settings/              # IDE 设置
├── st_ai_ws/               # ST.AI 工作区（run.ps1 步骤 5 可选产生 network.hex）
├── .gitignore
└── README.md
```

---

## 硬件说明

| 项目 | 说明 |
|------|------|
| 核心板 | 正点原子 STM32N647 核心板 |
| MCU | STM32N647A0HXQ (Cortex-M55 + Ethos NPU) |
| 外部 Flash | MX25UM25645G (256Mb OctoSPI NOR Flash) |
| 串口 | USART1, PB6(TX)/PB7(RX), 115200 8N1 |
| 调试接口 | 板载 ST-LINK, Type-C 连接 |
| External Loader | `MX25UM25645G_ATK-CNN647B_ExtMemLoader.stldr` |

> **注意**：主程序使用 **USART1** (PB6/PB7)，而非 USART3。需确保开发板的 USART1 引脚已引出至串口模块。

### BOOT 模式配置

| 模式 | BOOT0 | BOOT1 | 用途 |
|------|-------|-------|------|
| **Development boot** | 任意 | **3.3V** | 烧录/编程 |
| **Flash boot** | **GND** | **GND** | 正常运行 |

---

## 开发环境约定

| 项目 | 约定 |
|------|------|
| **操作系统** | Windows 11 / WSL2 (Ubuntu 22.04) |
| **Shell** | PowerShell (pwsh) 7+ (首选), bash (备用) |
| **Python** | 3.12 (Miniconda, 环境名 `stm32n6_ai`) |
| **ARM 工具链** | `arm-none-eabi-gcc` ≥ 14.3 (GNU Arm Embedded Toolchain) |
| **构建系统** | CMake ≥ 3.20 + Unix Makefiles |
| **ST.AI 中间件** | `D:/Downloads/NPU/4.0/Middlewares/ST/AI/` |
| **STM32CubeProgrammer** | ≥ 2.16.0 |
| **stedgeai-core** | ST Edge AI Core 工具 |
| **External Loader** | 需手动复制到 CubeProgrammer `ExternalLoader/` 目录 |

---

## 完整构建链

```
.\run.ps1
  ├─ create_model.py               → matrix_mul.onnx
  └─ stedgeai-core                 → stm32n647_appli/AI/ (network.h/c, network_data.h/c, ...)
                                       │
                                        ▼ CMake 交叉编译
                                   Debug/Network.elf
                                       │
                                        ▼ .\deploy.ps1 (STM32CubeProgrammer)
                                   烧录到内部 Flash (0x08000000)
```

### 分步构建（不依赖 run.ps1）

```powershell
# 1. 生成 ONNX 模型
conda activate stm32n6_ai
python create_model.py

# 2. 转换为 NPU 微码到 stm32n647_appli/AI/
stedgeai-core generate --model matrix_mul.onnx --target stm32n6 --type onnx --output stm32n647_appli/AI --allocate-inputs --allocate-outputs --verbosity 0

# 3. CMake 编译
cd stm32n647_appli
.\build.ps1

# 4. 生成烧录映像（build.ps1 已自动完成，手动方式如下）
# arm-none-eabi-objcopy -O ihex Debug/Network.elf Debug/Network.hex
# arm-none-eabi-objcopy -O binary Debug/Network.elf Debug/Network.bin

# 5. 烧录（Development boot 模式）
cd ..
.\deploy.ps1
```

### 初始化 conda 环境

```powershell
conda create -n stm32n6_ai python=3.12 -y
conda activate stm32n6_ai
pip install numpy onnx
```

---

## 软件架构说明

### 裸机实现（无 HAL）

项目采用**寄存器级裸机**实现，不依赖 STM32 HAL 库：

- **系统初始化** (`SystemInit`)：由启动文件调用，初始化 FPU 和 UART
- **FPU 初始化**：直接操作 `SCB->CPACR` 寄存器
- **UART 初始化**：直接操作 USART1、GPIOB 和 RCC 寄存器
  - 时钟：RCC_AHB5ENR (GPIOB) + RCC_APB2ENR (USART1)
  - GPIO：PB6/PB7 复用功能 AF7 (USART1)
  - 波特率：`BRR = HSI_64MHz / 115200`
- **printf 输出**：重定向 `__io_putchar()` 到 USART1，支持 `%f` 格式

### ST.AI 运行时

链接时需要 `NetworkRuntime1200_CM55_GCC.a` 运行时库（位于 `D:/Downloads/NPU/4.0/Middlewares/ST/AI/Lib/GCC/ARMCortexM55/`），提供 `forward_lite_dense_if32of32wf32` 等 NPU 核心加速函数。

### 推理流程（main.c）

```
1. stai_network_init()         → 初始化网络上下文
2. stai_network_set_activations() → 分配激活缓冲区
3. stai_network_get_inputs()   → 获取输入/输出指针
4. memcpy(input_ptr, data)     → 填充输入数据
5. stai_network_run()          → 执行 NPU 推理
6. printf(output_ptr)          → 打印推理结果
```

---

## create_model.py 核心原理

```python
from onnx import helper, TensorProto

X = helper.make_tensor_value_info('input', TensorProto.FLOAT, [1, 4])
Y = helper.make_tensor_value_info('output', TensorProto.FLOAT, [1, 2])

W = np.random.randn(4, 2).astype(np.float32)  # 矩阵 B
bias = np.zeros((2,), dtype=np.float32)

node = helper.make_node('Gemm', ['input', 'weights', 'bias'], ['output'],
                        alpha=1.0, beta=1.0, transA=0, transB=0)
```
修改 `[1,4]` / `[1,2]` / `[4,2]` 即可实现任意矩阵乘法 `A(m,n) × B(n,p) = C(m,p)`。

---

## CMake 构建说明

### 使用 STM32CubeIDE

项目包含 `.cproject` / `.project` 文件，可直接在 STM32CubeIDE 中打开 `stm32n647_appli/` 工程编译。

### 使用命令行 CMake

```powershell
cd stm32n647_appli
cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake -S . -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
make -C Debug -j
```

关键配置 (`CMakeLists.txt`)：
- **CPU**: `-mcpu=cortex-m55`
- **FPU**: `-mfpu=fpv5-d16`（双精度浮点）
- **ABI**: `-mfloat-abi=hard`
- **运行时**: `--specs=nano.specs` + `--specs=nosys.specs`
- **链接优化**: `--gc-sections`, `-u,_printf_float`
- **ST.AI 库**: `NetworkRuntime1200_CM55_GCC.a`

### 常见链接错误

| 错误 | 原因 | 修复 |
|------|------|------|
| `undefined reference to forward_lite_dense_if32of32wf32` | 缺少 ST.AI 运行时库 | 确认 `NetworkRuntime1200_CM55_GCC.a` 链接正确 |
| `unrecognized option '--major-image-version'` | 链接器路径错误（LD 被 MSYS2 替代） | 修正 `cubeide-gcc.cmake` 中的 `CMAKE_LINKER` |
| `undefined reference to _printf_float` | 未启用浮点打印 | 添加 `-Wl,-u,_printf_float` 链接标志 |
| `undefined reference to __DSB` | 使用了 CMSIS 函数 | 改用内联汇编 `__asm volatile("dsb")` |

---

## 内存布局

### 内部 Flash (0x08000000 ~ 0x09FFFFFF, 32MB)

| 段 | 地址 | 大小 | 内容 |
|----|------|------|------|
| `.isr_vector` | 0x34000400 | 0x34C | 中断向量表 |
| `.text` | 0x34000750 | ~17KB | 代码 + 运行时库 |
| `.rodata` | 0x34004A20 | ~2.4KB | 只读数据（权重等） |
| `.data` | 0x34080000 | 0x1C8 | 初始化的全局变量 |
| `.bss` | 0x340801C8 | 0x16C | 未初始化全局变量 |
| `_user_heap_stack` | 0x34080334 | 0x604 | 堆 + 栈 |

> 链接脚本 `STM32N647A0HXQ_FLASH.ld` 定义了完整的内存布局。

---

## 常见问题

**烧录失败 `failed to erase memory`** → BOOT1 接 3.3V，重新上电

**烧录失败 `external loader file does not exist`** → 复制 External Loader 到 CubeProgrammer 目录：
```powershell
copy "D:\BaiduNetdiskDownload\SoftwarePackage\External_Loader\MX25UM25645G_ATK-CNN647B\Binary\MX25UM25645G_ATK-CNN647B_ExtMemLoader.stldr" `
    "C:\Users\Yuan\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\ExternalLoader\"
```

**串口无输出** → 检查波特率 115200、数据位 8、停止位 1、无校验；确认 USART1 使用了 PB6(TX)/PB7(RX)；确认 BOOT 模式正确

**CMake 配置失败** → 确保 ARM GCC 工具链在 PATH 中：
```powershell
$env:PATH = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.3 rel1\bin;$env:PATH"
```

---

> **版本**: 2.0.0（CMake 裸机版）  
> **适用平台**: 正点原子 STM32N647 核心板  
> **仓库**: https://github.com/yuanchilin/stm32n6-ai-deploy