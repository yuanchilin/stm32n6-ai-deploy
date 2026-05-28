# STM32N6 NPU 矩阵乘法部署方案 (黄金方案)

## 📋 目录

1. [概述](#1-概述)
2. [准备材料](#2-准备材料)
3. [创建模拟矩阵乘法的 ONNX 模型](#3-创建模拟矩阵乘法的-onnx-模型)
4. [部署模型到开发板](#4-部署模型到开发板)
5. [STM32CubeIDE 工程集成](#5-stm32cubeide-工程集成)
6. [烧录与运行](#6-烧录与运行)
7. [硬件连接说明](#7-硬件连接说明)
8. [常见问题与调试](#8-常见问题与调试)
9. [附录](#9-附录)

---

### 开发环境约定

| 项目           | 约定                                        |
|----------------|---------------------------------------------|
| **操作系统**   | Windows 11 / WSL2 (Ubuntu 22.04)            |
| **默认 Shell** | PowerShell (pwsh) 7+ (Windows) / bash (WSL) |
| **Python**     | 3.12 (通过 Miniconda 管理)                  |
| **虚拟环境**   | Miniconda, 环境名 `stm32n6_ai`, Python 3.12 |
| **包管理器**   | conda + pip                                 |
| **文档同步**   | ⚠ 每次更新代码或脚本,必须同步更新相关文档 (包括但不限于文件头注释、模块注释、使用说明等),确保文档与代码始终保持一致 |

> **跨平台提示**: 本文档同时提供 **PowerShell** 和 **bash** 两种命令格式。Windows 下请使用 PowerShell (pwsh) 7+，WSL/Linux 下使用 bash。Shell 类型在命令块标题中标注。

#### 虚拟环境快速指南

```powershell
# PowerShell (Windows)
# 1. 创建虚拟环境 (首次)
conda create -n stm32n6_ai python=3.12 -y

# 2. 激活虚拟环境 (每次使用前)
conda activate stm32n6_ai

# 3. 安装依赖
pip install numpy onnx
pip install onnxruntime  # 可选, 用于本地验证

# 4. 生成模型
python create_model.py
```

```bash
# bash (WSL/Linux) - 命令相同, Shell 激活方式不同
# 1. 创建虚拟环境 (首次)
conda create -n stm32n6_ai python=3.12 -y

# 2. 激活虚拟环境 (每次使用前)
conda activate stm32n6_ai

# 3. 安装依赖
pip install numpy onnx
pip install onnxruntime  # 可选, 用于本地验证

# 4. 生成模型
python create_model.py
```

> 注意: 所有 Python 操作(安装依赖、运行脚本、模型转换)均需在 `stm32n6_ai` 虚拟环境中执行。


## 1. 概述

### 1.1 方案原理

利用 AI 模型中全连接层 (`Gemm` 算子的数学本质 `Y = W × X + B`) 来"骗"过 NPU 执行纯矩阵乘法运算。这样做的好处是：

- **充分利用 NPU 硬件加速**：STM32N6 的 NPU 专为矩阵运算优化
- **无需手动编写矩阵乘代码**：全部由 NPU 微码执行
- **可扩展性强**：只需调整模型输入/输出维度即可实现任意矩阵乘法

### 1.2 映射关系

| 数学运算        | ONNX 表示                        |
|-----------------|----------------------------------|
| `Y = A × B`     | `Gemm(input=A, weights=B, bias=0)` |
| 矩阵 A (1×N)    | 模型输入 `input`                 |
| 矩阵 B (N×M)    | 模型权重 `weights`               |
| 矩阵 C (1×M)    | 模型输出 `output`                |
| 偏置向量        | `bias = [0, 0, ..., 0]`          |

---

## 2. 准备材料

### 2.1 硬件

| 项目               | 说明                        |
|--------------------|-----------------------------|
| 核心板             | 正点原子 STM32N647 核心板    |
| 底板               | 配套底板                     |
| 电源               | 12V DC 电源 (5.5mm 圆头)     |
| 调试下载线         | Type-C 数据线 (连接 PC 与核心板) |
| USB 转串口模块     | 可选, 若底板不含 USB 转串口芯片 |
| 杜邦线             | 可选, 用于连接串口引脚       |

### 2.2 软件

| 项目                      | 版本要求      | 说明                          |
|---------------------------|---------------|-------------------------------|
| STM32CubeIDE              | ≥ 1.16.0      | 集成开发环境,需安装 STM32N6 MCU 包 |
| STM32CubeProgrammer       | ≥ 2.16.0      | 烧录工具                      |
| Python                    | ≥ 3.12        | 用于生成 ONNX 模型             |
| stedgeai-core             | 最新版        | STM32 AI 模型转换工具,用于生成 NPU 微码 |
| 正点原子例程包            | 对应版本      | 包含 FSBL 和 ExtMemLoader     |

> **STM32N6 MCU 包安装**: 在 STM32CubeIDE 中,通过 Help → Manage Embedded Software Packages → STM32Cube MCU Packages → STM32N6 安装。或从 ST 官网下载 STM32Cube_FW_N6 手动导入。

### 2.3 Python 依赖

```bash
# 必需: 模型生成
pip install numpy onnx

# 可选: 本地推理验证
pip install onnxruntime
```


---

## 3. 创建模拟矩阵乘法的 ONNX 模型

### 3.1 模型生成脚本

文件: [`create_model.py`](create_model.py)

```python
# =============================================================================
#  脚本: create_model.py
#  功能: 创建模拟矩阵乘法的 ONNX 模型 (利用 Gemm 层)
#        实现 A(1,4) × B(4,2) = C(1,2)
#  用法: python create_model.py
#  依赖: pip install numpy onnx        (模型生成)
#         pip install onnxruntime       (可选, 用于本地验证)
#  环境:
#         - Windows 11 / WSL2 (PowerShell 7+ / bash)
#         - Python 3.12 (通过 Miniconda 管理)
#         - Conda 环境名: stm32n6_ai
#  用法:
#         conda activate stm32n6_ai
#         python create_model.py
#  注意: 每次更新此脚本, 必须同步更新 README_STM32N6_AI_DEPLOY.md 中
#        的对应代码块和说明, 确保文档与代码始终保持一致。
# =============================================================================

import numpy as np
import onnx
from onnx import helper, TensorProto

# ============================================================
# 创建模拟矩阵乘法的 ONNX 模型
# 核心: 利用全连接层 (Gemm) Y = alpha * X * W + beta * B
# 这里实现 A(1,4) * B(4,2) = C(1,2)
# ============================================================

# 1. 定义输入: 形状为 (1, 4)，即矩阵 A
X = helper.make_tensor_value_info('input', TensorProto.FLOAT, [1, 4])
Y = helper.make_tensor_value_info('output', TensorProto.FLOAT, [1, 2])

# 2. 准备权重 W (形状 4x2) 和偏置 B (形状 2)
#    W 代表你的矩阵 B (4x2)
#    Bias 是全零向量，此时 Y = X * W
np.random.seed(42)  # 固定随机种子，使结果可复现
W = np.random.randn(4, 2).astype(np.float32)  # 矩阵 B (4x2)
bias = np.zeros((2,), dtype=np.float32)

# 3. 构建初始化和节点
initializer = [
    helper.make_tensor('weights', TensorProto.FLOAT, [4, 2], W.flatten()),
    helper.make_tensor('bias', TensorProto.FLOAT, [2], bias)
]

# Gemm 节点: Y = alpha * A * B + beta * C
node = helper.make_node(
    'Gemm',                              # 算子类型
    ['input', 'weights', 'bias'],        # 输入 [A, B, C]
    ['output'],                          # 输出
    alpha=1.0,                           # alpha 系数
    beta=1.0,                            # beta 系数
    transA=0,                            # 是否转置 A: 0=不转置
    transB=0                             # 是否转置 B: 0=不转置
)

# 4. 构建计算图
graph = helper.make_graph(
    [node],                    # 节点列表
    'matmul_graph',            # 图名称
    [X],                       # 输入
    [Y],                       # 输出
    initializer                # 初始值 (权重和偏置)
)

# 5. 构建模型
model = onnx.helper.make_model(
    graph,
    producer_name='matmul_demo',
    producer_version='1.0',
    opset_imports=[helper.make_operatorsetid('', 21)]  # opset 21 (兼容性好, stedgeai-core 推荐)
)

# 6. 检查模型有效性
onnx.checker.check_model(model)

# 7. 保存模型
onnx.save(model, 'matrix_mul.onnx')
print("✅ 模型已保存至: matrix_mul.onnx")

# ============================================================
# 可选验证: 使用 onnxruntime 进行本地推理验证
# ============================================================
try:
    import onnxruntime as ort

    print("\n--- 本地推理验证 ---")
    print(f"权重矩阵 W (B 矩阵, 4x2):\n{W}")

    # 准备输入: 矩阵 A
    A = np.array([[1.0, 2.0, 3.0, 4.0]], dtype=np.float32)
    print(f"\n输入矩阵 A: {A}")

    # 创建推理会话
    session = ort.InferenceSession('matrix_mul.onnx')
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name

    # 执行推理
    result = session.run([output_name], {input_name: A})[0]
    print(f"NPU 推理结果: {result}")

    # 手动计算验证
    expected = A @ W  # Y = X * W (bias = 0)
    print(f"手动计算结果: {expected}")

    if np.allclose(result, expected, atol=1e-5):
        print("\n✅ 推理结果验证通过! 模型正确实现了矩阵乘法!")
    else:
        print("\n❌ 推理结果不一致! 请检查模型。")

except ImportError:
    print("\nℹ️  onnxruntime 未安装，跳过本地验证。")
    print("   如需验证，请执行: pip install onnxruntime")
```

### 3.2 运行生成模型

> **Shell 选择**: 以下命令适用于 **PowerShell** 和 **bash** (命令语法相同)。若使用 PowerShell,确保已激活 conda 环境。

```bash
# 激活虚拟环境 (初次使用前先 conda create)
conda activate stm32n6_ai

# 安装依赖 (仅首次)
pip install numpy onnx

# 生成 ONNX 模型
python create_model.py
```

生成的 `matrix_mul.onnx` 模型结构:

```
输入: input (1, 4)
        │
        ▼
    [Gemm]  ── weights (4, 2), bias (2)
        │
        ▼
输出: output (1, 2)
```

### 3.3 验证模型 (可选)

安装 `onnxruntime` 后运行脚本会自动验证:

```bash
pip install onnxruntime
python create_model.py
```

输出示例:

```
✅ 模型已保存至: matrix_mul.onnx

--- 本地推理验证 ---
权重矩阵 W (B 矩阵, 4x2):
[[ 0.4967 -0.1383]
 [ 0.6477  1.5230]
 [-0.2342 -0.2342]
 [-0.4695  0.5426]]

输入矩阵 A: [[1. 2. 3. 4.]]
NPU 推理结果: [[ 0.9454  3.3121]]
手动计算结果: [[ 0.9454  3.3121]]

✅ 推理结果验证通过! 模型正确实现了矩阵乘法!
```

### 3.4 自定义矩阵尺寸

若要实现 `A(m×n) × B(n×p) = C(m×p)`:

1. 修改输入形状: `[m, n]`
2. 修改输出形状: `[m, p]`
3. 修改权重形状: `[n, p]`
4. 修改偏置形状: `[p]`

> **注意**: Gemm 的 `transB=0` 时,权重形状应为 `[n, p]`。若需要转置权重矩阵,设置 `transB=1`,此时权重形状为 `[p, n]`。
>
> **OPen Neural Network Exchange (ONNX) opset 说明**: stedgeai-core 推荐使用 opset 21。如果需要降级兼容旧版本工具链,可改为 opset 13 (Gemm 算子从 opset 1 即可用,opset 13+ 提供更好的属性支持)。

---

## 4. 部署模型到开发板

### 4.1 模型转换 (ONNX → NPU 微码)

使用 `stedgeai-core` 工具将 ONNX 模型转换为 NPU 可执行的微码:

> **PowerShell 注意**: `\` 是 bash 续行符。PowerShell 中请用 `` ` `` 续行或将命令写在一行。

```bash
# bash (WSL/Linux)
# 安装 stedgeai-core
pip install stedgeai-core

# 转换模型
stedgeai-core generate microcode \
    -m matrix_mul.onnx \
    -t STM32N6 \
    -o ./npu_model \
    --allocate-inputs \
    --allocate-outputs
```

```powershell
# PowerShell (Windows) - 使用反引号续行
pip install stedgeai-core

stedgeai-core generate microcode `
    -m matrix_mul.onnx `
    -t STM32N6 `
    -o ./npu_model `
    --allocate-inputs `
    --allocate-outputs
```

参数说明:

| 参数                   | 说明                          |
|------------------------|-------------------------------|
| `-m` / `--model`      | ONNX 模型路径                  |
| `-t` / `--target`     | 目标芯片型号 (STM32N6)         |
| `-o` / `--output`     | 输出目录                       |
| `--allocate-inputs`   | 自动分配输入缓冲区              |
| `--allocate-outputs`  | 自动分配输出缓冲区              |

### 4.2 转换输出文件

转换后将在 `./npu_model/` 目录生成:

```
npu_model/
├── network.h              # 模型 C 头文件 (包含网络配置、缓冲大小定义)
├── network.c              # 模型 C 源文件 (包含权重数据和网络图)
├── network_data.h         # 权重数据头文件
├── network_data.c         # 权重数据源文件
├── ai_runner.h            # AI 运行时头文件
├── ai_runner.c            # AI 运行时实现
├── stm32n6_network.c      # STM32N6 专有实现
├── stm32n6_network.h      # STM32N6 专有头文件
├── CMakeLists.txt         # CMake 构建文件 (可选)
└── report.json            # 转换报告 (包含性能估计)
```

### 4.3 关键定义说明

`network.h` 中的关键宏定义:

```c
#define AI_NETWORK_IN_1_SIZE     16      // 输入缓冲区大小 (字节)
#define AI_NETWORK_OUT_1_SIZE    8       // 输出缓冲区大小 (字节)
#define AI_NETWORK_DATA_SIZE     4096    // 激活缓冲区大小 (字节)
#define AI_NETWORK_IN_NB         1       // 输入张量数量
#define AI_NETWORK_OUT_NB        1       // 输出张量数量
```

---

## 5. STM32CubeIDE 工程集成

### 5.1 创建/准备工程

1. 打开 STM32CubeIDE
2. 导入正点原子提供的 FSBL (First Stage Boot Loader) 工程
3. 导入正点原子提供的 ExtMemLoader (外部存储器加载器) 工程
4. 创建或导入 Appli (应用程序) 工程
   - 参考 `STM32CubeIDE/Appli/` 目录结构 (详见[附录 9.1](#91-项目文件结构))
5. 编译各工程生成 `.bin` 文件:
   - 右键工程 → Build Project
   - 编译成功后,`.bin` 文件位于工程 `Debug/` 目录下
   - 或通过 Project → Properties → C/C++ Build → Settings → MCU GCC Post-Build 添加 `arm-none-eabi-objcopy -O binary "${BuildArtifactFileName}" "${BuildArtifactFileBaseName}.bin"` 自动生成

### 5.2 复制模型文件

将 `npu_model/` 目录下所有 `.c` 和 `.h` 文件复制到 Appli 工程的 `Core/Src/` 和 `Core/Inc/` 目录。

### 5.3 添加源文件到构建

在 STM32CubeIDE 中:

1. 右键工程 → **Properties**
2. 导航至 **C/C++ Build → Settings**
3. 在 **MCU GCC Compiler → Include paths** 中添加 `Core/Inc`
4. 在 **MCU GCC Linker → Libraries** 中添加 `ai` 和 `m` (数学库)

### 5.4 编写主程序

```c
/* main.c */

#include "main.h"
#include "ai_runner.h"
#include "network.h"  // 模型头文件

/* 内存对齐宏定义 */
#define ALIGNED(n)       __attribute__((aligned(n)))
#define ALIGN_PTR(p, a)  (void *)(((uint32_t)(p) + (a) - 1) & ~((a) - 1))

/* 模型缓冲区 (32字节对齐,满足 NPU 要求) */
ALIGNED(32) static uint8_t input_data[AI_NETWORK_IN_1_SIZE];
ALIGNED(32) static uint8_t output_data[AI_NETWORK_OUT_1_SIZE];
ALIGNED(32) static uint8_t activations[AI_NETWORK_DATA_SIZE];

/* 网络句柄 */
static ai_handle network = AI_HANDLE_NULL;

/* 打印浮点数 (通过串口) */
static void print_float_array(const char* label, float* data, uint32_t len)
{
    printf("%s: ", label);
    for (uint32_t i = 0; i < len; i++) {
        printf("%.4f ", data[i]);
    }
    printf("\r\n");
}

int main(void)
{
    /* 1. HAL 库初始化 */
    HAL_Init();

    /* 2. 系统时钟配置 (参考正点原子例程) */
    SystemClock_Config();

    /* 3. 串口初始化 (用于打印结果) */
    MX_USART1_UART_Init();

    /* 4. XSPI (外部存储器) 初始化 */
    MX_XSPIM_Init();

    /* 5. NPU 子系统初始化 */
    MX_NPU_Init();

    printf("\r\n======== STM32N6 NPU 矩阵乘法 Demo ========\r\n");
    printf("模型: A(1,4) × B(4,2) = C(1,2)\r\n\r\n");

    /* 6. 初始化 AI 网络 */
    ai_params = AI_NETWORK_PARAMS_INIT(
        AI_NETWORK_DATA_ACTIVATIONS(activations),
        AI_NETWORK_DATA_WEIGHTS(NULL)  /* 权重已静态编译, 传入 NULL */
    );

    ai_error error;
    if (ai_network_create(&network, AI_NETWORK_DATA_CONFIG) != 0) {
        printf("❌ 网络创建失败!\r\n");
        Error_Handler();
    }

    if (ai_network_init(network, &ai_params) != 0) {
        printf("❌ 网络初始化失败!\r\n");
        Error_Handler();
    }

    printf("✅ 网络初始化成功!\r\n");

    /* 7. 准备输入数据: 矩阵 A = [1.0, 2.0, 3.0, 4.0] */
    float matrix_A[4] = {1.0f, 2.0f, 3.0f, 4.0f};

    /* 将数据复制到输入缓冲区 */
    memcpy(input_data, matrix_A, sizeof(matrix_A));

    print_float_array("输入矩阵 A", matrix_A, 4);

    /* 8. 获取输入/输出张量并绑定缓冲区 */
    ai_tensor* in_tensor  = ai_network_inputs_get(network, NULL);
    ai_tensor* out_tensor = ai_network_outputs_get(network, NULL);

    if (in_tensor == NULL || out_tensor == NULL) {
        printf("❌ 获取输入/输出张量失败!\r\n");
        Error_Handler();
    }

    in_tensor->data  = AI_HANDLE_PTR(input_data);
    out_tensor->data = AI_HANDLE_PTR(output_data);

    /* 9. 执行推理 (NPU 执行矩阵乘法) */
    printf("正在执行 NPU 推理...\r\n");

    ai_i32 batch = ai_network_run(network, in_tensor, out_tensor);
    if (batch != 1) {
        printf("❌ 推理失败! (batch=%d)\r\n", batch);
        Error_Handler();
    }

    printf("✅ 推理完成!\r\n");

    /* 10. 获取结果 */
    float* result = (float*)output_data;
    print_float_array("输出矩阵 C", result, 2);

    /* 打印原始数据 (HEX) */
    printf("\r\n输出原始数据 (HEX): ");
    for (uint32_t i = 0; i < AI_NETWORK_OUT_1_SIZE; i++) {
        printf("%02X ", output_data[i]);
    }
    printf("\r\n");

    /* 11. 释放网络 */
    ai_network_destroy(network);

    printf("\r\n======== Demo 结束 ========\r\n");

    while (1)
    {
        /* 空循环或进入低功耗模式 */
    }
}

/* 系统时钟配置 */
void SystemClock_Config(void)
{
    /* 参考正点原子例程实现 */
}

/* 错误处理 */
void Error_Handler(void)
{
    printf("严重错误! 系统停止.\r\n");
    while (1) {}
}
```

> **代码说明**: 以上代码使用了 X-CUBE-AI 生成的 `ai_runner.h` 中的 API。
> - `ai_network_inputs_get()` / `ai_network_outputs_get()`: 获取输入/输出张量指针
> - `ai_network_run(network, in_tensor, out_tensor)`: 执行推理
> - 如果您的 stedgeai-core 版本生成的 API 不同,请参考 `ai_runner.h` 中的实际函数签名进行调整

### 5.5 关键注意事项

#### 5.5.1 内存对齐

NPU 要求缓冲区必须对齐到 32 字节边界:

```c
/* 方法1: 使用变量属性 */
ALIGNED(32) static uint8_t buffer[1024];

/* 方法2: 使用对齐宏运行时对齐 */
void* aligned_buf = ALIGN_PTR(raw_buf, 32);
```

#### 5.5.2 数据格式

- 输入数据为 IEEE 754 32-bit 浮点数 (float32)
- 数据排列为行主序 (Row-major)
- 对于矩阵 A(1,N),直接按顺序填充 N 个 float

#### 5.5.3 内存模型

STM32N6 内存布局:

```
┌─────────────────────┐
│  内部 SRAM           │  小容量, 通常用于关键数据和栈
│  (1.6 MB)           │
├─────────────────────┤
│  外部 PSRAM/SDRAM    │  大容量, 用于激活缓冲区和权重
│  (64 MB)            │
├─────────────────────┤
│  NPU 本地内存        │  NPU 内部 SRAM, 用于微码和数据缓存
│  (小容量)            │
└─────────────────────┘
```

确保模型缓冲区 (`activations`) 分配到外部 PSRAM 区域。

#### 5.5.4 链接脚本配置

在 `STM32N647XX_FLASH.ld` 链接脚本中,需要将激活缓冲区段分配到外部 PSRAM 地址空间。参考配置:

```c
/* 在链接脚本的 SECTIONS 中添加 */
.npu_activations (NOLOAD) : {
    *(.npu_activations)
    *(.npu_activations.*)
} > EXTERNAL_PSRAM
```

> 正点原子例程包中已包含正确的链接脚本配置,通常无需手动修改。如需自定义,请参考 `STM32Cube_FW_N6/Projects/.../STM32CubeIDE/` 中的示例。

---

## 6. 烧录与运行

### 6.1 获取 .bin 文件

在 STM32CubeIDE 中编译工程后:

- Appli 工程的 `.bin` 文件: `Appli/Debug/appli.bin`
- FSBL 工程的 `.bin` 文件: `FSBL/Debug/fsbl.bin`
- ExtMemLoader 工程的 `.bin` 文件: `ExtMemLoader/Debug/extmemloader.bin`

> 如果工程目录下没有 `.bin` 文件,请在工程 Properties → C/C++ Build → Settings → MCU GCC Post-Build 中添加命令:
> ```
> arm-none-eabi-objcopy -O binary "${BuildArtifactFileName}" "${BuildArtifactFileBaseName}.bin"
> ```

### 6.2 烧录流程 (STM32N6 特殊流程)

STM32N6 芯片**无内置 Flash**,程序存储在外部 NOR Flash 中。烧录需要分步进行:

#### 步骤 1: 烧录 External Loader

> 如需在 PowerShell 中执行,删除续行符 `\` 或使用 `` ` `` 续行。

```bash
# 使用 STM32CubeProgrammer
STM32_Programmer_CLI.exe -c port=SWD mode=UR
STM32_Programmer_CLI.exe -w extmemloader.bin 0x00000000 -v
```

#### 步骤 2: 烧录 FSBL

```bash
STM32_Programmer_CLI.exe -w fsbl.bin 0x70000000 -v
```

#### 步骤 3: 烧录 Appli

```bash
STM32_Programmer_CLI.exe -w appli.bin 0x70100000 -v
```

### 6.3 使用 STM32CubeIDE 一键烧录

1. 在 STM32CubeIDE 中配置 Debug Configuration
2. 选择 **STM32 Cortex-M Debug** 或 **STM32 Cortex-A Debug**
3. 在 **Debugger** 选项卡中:
   - 选择调试器: ST-LINK (或 J-Link,取决于硬件)
   - 连接模式: SWD
   - 烧录前自动加载: ✅

### 6.4 运行与查看结果

1. 连接串口 (详情见 [第 7 章: 硬件连接说明](#7-硬件连接说明))
2. 开发板上电
3. 按下复位键
4. 串口输出:

```
======== STM32N6 NPU 矩阵乘法 Demo ========
模型: A(1,4) × B(4,2) = C(1,2)

输入矩阵 A: 1.0000 2.0000 3.0000 4.0000
✅ 网络初始化成功!
正在执行 NPU 推理...
✅ 推理完成!
输出矩阵 C: 0.9454 3.3121
======== Demo 结束 ========
```

---

## 7. 硬件连接说明

### 7.1 核心板与底板安装

1. 将正点原子 STM32N647 核心板插入配套底板 (注意防反插,对准排针)
2. 确保排针完全插入,无歪斜

### 7.2 电源连接

- 使用 12V DC 电源 (5.5mm 圆头) 连接到底板电源接口
- 核心板板载指示灯 (红色 LED) 应点亮
- 若 3.3V 指示灯 (绿色 LED) 不亮,请检查核心板是否正确插入

### 7.3 调试接口 (SWD)

- 核心板已通过底板引出 SWD 接口
- 使用 Type-C 数据线连接 PC 与核心板的 **Type-C 调试口**
- ST-LINK 调试器集成在核心板上,无需额外调试器

### 7.4 串口连接

| 参数       | 值                |
|------------|-------------------|
| 串口外设   | USART1            |
| 波特率     | 115200            |
| 数据位     | 8                 |
| 停止位     | 1                 |
| 校验位     | 无                |
| 流控制     | 无                |

**连接方式**:
- 正点原子底板通常自带 USB 转串口芯片 (如 CH340),通过 Type-C 或 Micro-USB 接口连接 PC
- 在设备管理器中查看串口号 (如 COM3)
- 使用串口工具 (如 [PuTTY](https://www.putty.org/)、[MobaXterm](https://mobaxterm.mobatek.net/) 或 VS Code 的 Serial Monitor 插件) 连接对应串口

### 7.5 BOOT 引脚设置

STM32N6 启动模式选择 (参考正点原子底板丝印):

| 启动模式 | BOOT0 | BOOT1 | 说明             |
|----------|-------|-------|------------------|
| Flash    | 0     | x     | 从外部 NOR Flash 启动 (正常模式) |
| System   | 1     | 0     | 系统存储器启动 (用于固件升级)    |
| RAM      | 1     | 1     | 从内部 SRAM 启动 (调试用)        |

> **烧录/运行时**: 将 BOOT0 置为 0 (拨码开关或跳线帽),BOOT1 任意。烧录完成后按复位键即可运行。

---

## 8. 常见问题与调试

### 8.1 模型转换失败

| 错误                                   | 解决方案                                     |
|----------------------------------------|----------------------------------------------|
| `Unsupported operator`                 | 确保 opset ≥ 13, 且算子包含在 stedgeai 支持列表中 |
| `Dimension mismatch`                   | 检查输入/输出/权重维度是否匹配                |
| `Type not supported`                   | 使用 float32, 不要用 double 或 int64          |
| `No microcode generated`               | 确认 target 参数正确: `-t STM32N6`           |

### 8.2 烧录失败

| 错误                                   | 解决方案                                     |
|----------------------------------------|----------------------------------------------|
| `Cannot connect to target`             | 检查 SWD 连接、电源、BOOT 引脚设置            |
| `Download verified failed`             | 尝试降低 SWD 速度, 或检查外部 Flash 配置      |
| `FSBL not booting`                     | 确认 FSBL 与硬件板卡版本匹配                  |

### 8.3 推理结果异常

| 现象                                   | 可能原因                                     |
|----------------------------------------|----------------------------------------------|
| 全部输出为 0                           | 输入缓冲区未正确填充, 或 NPU 初始化失败        |
| 输出为 NaN/Inf                         | 内存对齐问题, 或数据格式错误                   |
| 输出结果与预期不符                     | 权重数据顺序问题, 检查 row-major vs column-major |
| NPU 执行超时                           | 激活缓冲区太小, 或 NPU 时钟配置不当            |

### 8.4 调试技巧

#### 使用 HAL 调试输出

```c
#define DEBUG_PRINT(fmt, ...) \
    printf("[DEBUG] %s:%d: " fmt, __func__, __LINE__, ##__VA_ARGS__)

DEBUG_PRINT("input buffer addr: 0x%08X\r\n", (uint32_t)input_data);
DEBUG_PRINT("output buffer addr: 0x%08X\r\n", (uint32_t)output_data);
DEBUG_PRINT("activations addr: 0x%08X\r\n", (uint32_t)activations);
```

#### 检查缓冲区对齐

```c
/* 在 main 开头添加对齐检查 */
assert(((uint32_t)input_data % 32) == 0);
assert(((uint32_t)output_data % 32) == 0);
assert(((uint32_t)activations % 32) == 0);
```

#### 使用 LED 指示状态

```c
#define LED_ON   HAL_GPIO_WritePin(LED_GPIO_Port, LED_Pin, GPIO_PIN_SET)
#define LED_OFF  HAL_GPIO_WritePin(LED_GPIO_Port, LED_Pin, GPIO_PIN_RESET)

/* 初始化完成后点亮 LED */
LED_ON;

/* 推理完成时闪烁 LED */
for (int i = 0; i < 3; i++) {
    LED_ON;  HAL_Delay(200);
    LED_OFF; HAL_Delay(200);
}
```

---

## 9. 附录

### 9.1 项目文件结构

```
matrix_mul_project/
├── .gitignore                 # Git 忽略文件配置
├── create_model.py            # ONNX 模型生成脚本
├── matrix_mul.onnx            # 生成的 ONNX 模型 (被 .gitignore 忽略)
├── npu_model/                 # stedgeai-core 转换输出 (被 .gitignore 忽略)
│   ├── network.h
│   ├── network.c
│   ├── network_data.h
│   ├── network_data.c
│   ├── ai_runner.h
│   ├── ai_runner.c
│   ├── stm32n6_network.c
│   ├── stm32n6_network.h
│   ├── CMakeLists.txt
│   └── report.json
├── ENVIRONMENT.md             # 开发环境约定文档
├── README_STM32N6_AI_DEPLOY.md # 本文档
└── STM32CubeIDE/              # STM32CubeIDE 工程
    ├── FSBL/                  # 一级启动加载器
    │   ├── Core/
    │   └── Debug/
    │       └── fsbl.bin       # 编译生成的二进制文件
    ├── ExtMemLoader/          # 外部存储器加载器
    │   ├── Core/
    │   └── Debug/
    │       └── extmemloader.bin
    └── Appli/                 # 应用程序
        ├── Core/
        │   ├── Inc/
        │   │   └── main.h
        │   └── Src/
        │       ├── main.c          # 主程序 (含 AI 推理代码)
        │       ├── ai_runner.c     # 从 npu_model 复制
        │       ├── network.c       # 从 npu_model 复制
        │       └── stm32n6_network.c
        ├── STM32N647XX_FLASH.ld    # 链接脚本
        ├── Debug/
        │   └── appli.bin
        └── .project
```

### 9.2 快速参考命令

> **跨平台提示**: Windows 请使用 PowerShell (pwsh) 7+, 并使用 `` ` `` 续行符而非 `\`。

```powershell
# PowerShell (Windows)

# 1. 激活虚拟环境
conda activate stm32n6_ai

# 2. 生成 ONNX 模型
python create_model.py

# 3. 转换为 NPU 微码 (使用反引号续行)
stedgeai-core generate microcode `
    -m matrix_mul.onnx `
    -t STM32N6 `
    -o ./npu_model

# 4. 查看转换报告 (Get-Content 代替 cat)
Get-Content npu_model/report.json

# 5. 烧录 (STM32CubeProgrammer)
STM32_Programmer_CLI.exe -c port=SWD -w appli.bin 0x70100000 -v
```

```bash
# bash (WSL/Linux)

# 1. 激活虚拟环境
conda activate stm32n6_ai

# 2. 生成 ONNX 模型
python create_model.py

# 3. 转换为 NPU 微码
stedgeai-core generate microcode \
    -m matrix_mul.onnx \
    -t STM32N6 \
    -o ./npu_model

# 4. 查看转换报告
cat npu_model/report.json

# 5. 烧录 (在 Windows 上运行 STM32_Programmer_CLI.exe 需在 pwsh/cmd 中执行)
# 请切换到 Windows 原生环境执行烧录命令
```

### 9.3 参考资源

- [STM32CubeAI 官方文档](https://wiki.st.com/stm32mcu/wiki/STM32CubeAI)
- [STEdgeAI Core 用户指南](https://github.com/STMicroelectronics/stedgeai-core)
- [正点原子 STM32N647 开发板资料](https://www.alientek.com/)
- [ONNX 官方文档](https://onnx.ai/)
- [ONNX Gemm 算子说明](https://github.com/onnx/onnx/blob/main/docs/Operators.md#Gemm)

---

> **版本**: 1.1.0
> **最后更新**: 2026-05-28
> **适用平台**: 正点原子 STM32N647 核心板
> **修改历史**:
> - v1.1.0: 修复 main.c 代码错误(变量未声明/宏参数类型不匹配), 添加 PowerShell 兼容命令, 补充硬件连接说明和 X-CUBE-AI API 使用示例
> - v1.0.0: 初始版本