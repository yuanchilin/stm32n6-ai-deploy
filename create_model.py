"""生成模拟矩阵乘法 A(1,4)×B(4,2)=C(1,2) 的 ONNX 模型"""

import numpy as np
import onnx
from onnx import helper, TensorProto

# 输入 (1,4) → Gemm → 输出 (1,2)
X = helper.make_tensor_value_info('input', TensorProto.FLOAT, [1, 4])
Y = helper.make_tensor_value_info('output', TensorProto.FLOAT, [1, 2])

np.random.seed(42)
W = np.random.randn(4, 2).astype(np.float32)  # 矩阵 B
bias = np.zeros((2,), dtype=np.float32)

node = helper.make_node('Gemm', ['input', 'weights', 'bias'], ['output'],
                        alpha=1.0, beta=1.0, transA=0, transB=0)

graph = helper.make_graph([node], 'matmul_graph', [X], [Y],
    [helper.make_tensor('weights', TensorProto.FLOAT, [4, 2], W.flatten()),
     helper.make_tensor('bias', TensorProto.FLOAT, [2], bias)])

model = helper.make_model(graph, producer_name='matmul_demo',
    opset_imports=[helper.make_operatorsetid('', 21)])

onnx.checker.check_model(model)
onnx.save(model, 'matrix_mul.onnx')
print(f"[OK] matrix_mul.onnx 已保存 (权重 W 形状 {W.shape})")