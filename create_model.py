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
#        的对应代码块和说明, 确保文档与代码保持一致。
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
    opset_imports=[helper.make_operatorsetid('', 21)]  # opset 21 (兼容性好)
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