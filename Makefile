# STM32N6 NPU 一键部署
.PHONY: all run clean

all: run

VERBOSE = @
ifeq (1,$(V))
VERBOSE =
endif

# 自动检测 stedgeai
STEDGEAI_PATH = $(wildcard D:/ST/STEdgeAI/*/Utilities/windows/stedgeai.exe)
STEDGEAI = $(if $(STEDGEAI_PATH),local,pip)

run:
	$(VERBOSE) pwsh -NoProfile -File run.ps1

clean:
	rm -f matrix_mul.onnx
	rm -rf npu_model logs st_ai_ws
	$(info [OK] 已清理)