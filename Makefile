# STM32N6 NPU 一键部署
.PHONY: all run build clean

all: run

VERBOSE = @
ifeq (1,$(V))
VERBOSE =
endif

# 自动检测 stedgeai
STEDGEAI_PATH = $(wildcard D:/ST/STEdgeAI/*/Utilities/windows/stedgeai.exe)
STEDGEAI = $(if $(STEDGEAI_PATH),local,pip)

run:
ifeq (1,$(CLEAN))
	$(VERBOSE) pwsh -NoProfile -File run.ps1 -Clean
else ifeq (1,$(REBUILD))
	$(VERBOSE) pwsh -NoProfile -File run.ps1 -Rebuild
else
	$(VERBOSE) pwsh -NoProfile -File run.ps1
endif

build:
ifeq (1,$(CLEAN))
	$(VERBOSE) pwsh -NoProfile -File build.ps1 -Clean
else ifeq (1,$(REBUILD))
	$(VERBOSE) pwsh -NoProfile -File build.ps1 -Rebuild
else
	$(VERBOSE) pwsh -NoProfile -File build.ps1
endif

clean:
	rm -f matrix_mul.onnx
	rm -rf stm32n647_appli/AI stm32n647_appli/ai logs st_ai_ws
	$(info [OK] 已清理)
