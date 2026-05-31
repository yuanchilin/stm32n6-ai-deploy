#############################################################################################################################
# file:  CMakeLists.txt
# brief: Template "CMakeLists.txt" for building of executables and static libraries.
#
# usage: Edit "VARIABLES"-section to suit project requirements.
#        For debug build:
#          cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake  -S ./ -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
#          make -C Debug VERBOSE=1 -j
#        For release build:
#          cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake  -S ./ -B Release -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
#          make -C Release VERBOSE=1 -j
#############################################################################################################################
cmake_minimum_required(VERSION 3.20)

###################### CONSTANTS ######################################
set (PROJECT_TYPE_EXECUTABLE          "exe")
set (PROJECT_TYPE_STATIC_LIBRARY      "static-lib")
set (MCPU_CORTEX_M0				      "-mcpu=cortex-m0")
set (MCPU_CORTEX_M0PLUS				  "-mcpu=cortex-m0plus")
set (MCPU_CORTEX_M3				      "-mcpu=cortex-m3")
set (MCPU_CORTEX_M4				      "-mcpu=cortex-m4")
set (MCPU_CORTEX_M7				      "-mcpu=cortex-m7")
set (MCPU_CORTEX_M33				  "-mcpu=cortex-m33")
set (MCPU_CORTEX_M55				  "-mcpu=cortex-m55")
set (MCPU_CORTEX_M85				  "-mcpu=cortex-m85")
set (MFPU_FPV4_SP_D16                 "-mfpu=fpv4-sp-d16")
set (MFPU_FPV4                        "-mfpu=vfpv4")
set (MFPU_FPV5_D16                    "-mfpu=fpv5-d16")
set (RUNTIME_LIBRARY_REDUCED_C        "--specs=nano.specs")
set (RUNTIME_LIBRARY_STD_C            "")
set (RUNTIME_LIBRARY_SYSCALLS_MINIMAL "--specs=nosys.specs")
set (RUNTIME_LIBRARY_SYSCALLS_NONE    "")
set (MFLOAT_ABI_SOFTWARE              "-mfloat-abi=soft")
set (MFLOAT_ABI_HARDWARE              "-mfloat-abi=hard")
set (MFLOAT_ABI_MIX                   "-mfloat-abi=softfp")
#######################################################################

###################### VARIABLES ######################################
set (PROJECT_NAME             "Network")
set (PROJECT_TYPE             "exe")
set (LINKER_SCRIPT            "../STM32N647A0HXQ_FLASH.ld")
set (MCPU                     "-mcpu=cortex-m55")
set (MFPU                 "-mfpu=fpv5-d16")
set (MFLOAT_ABI               "-mfloat-abi=hard")
set (RUNTIME_LIBRARY          "--specs=nano.specs")
set (RUNTIME_LIBRARY_SYSCALLS "--specs=nosys.specs")


set (PROJECT_SOURCES
	# LIST SOURCE FILES HERE
	Startup/startup_stm32n647x0hxq.s
	# Sources/main.c
	Core/Src/main.c
	Core/Src/stm32n6xx_it.c
	Core/Src/stm32n6xx_hal_msp.c
	Core/Src/secure_nsc.c
	Core/Src/system_stm32n6xx_s.c
	Sources/syscalls.c
	Sources/sysmem.c
	AI/network.c
	AI/network_data.c

	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/SYS/sys.c
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/HyperRAM/hyperram.c
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/LED/led.c
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/UART/uart.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_cortex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_dma.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_dma_ex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_exti.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_gpio.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_pwr.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_pwr_ex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_rcc.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_rcc_ex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_rif.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_tim.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_tim_ex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_uart.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_uart_ex.c
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Src/stm32n6xx_hal_xspi.c


	)

set (PROJECT_DEFINES
	# LIST COMPILER DEFINITIONS HERE
	DEBUG
	STM32N647xx
	USE_HAL_DRIVER
    )

set (PROJECT_INCLUDES
	# LIST INCLUDE DIRECTORIES HERE
	Sources
	AI
	# AI/Inc
	Core/Inc
	Secure_nsclib
	D:/Downloads/NPU/4.0/Middlewares/ST/AI/Inc
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/SYS
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/HyperRAM
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/LED
	D:/BaiduNetdiskDownload/SoftwarePackage/Drivers/BSP/UART
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/CMSIS/Device/ST/STM32N6xx/Include
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/CMSIS/Include
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Inc
	D:/BaiduNetdiskDownload/SoftwarePackage/STM32Cube_FW_N6_V1.0.0/Drivers/STM32N6xx_HAL_Driver/Inc/Legacy
    )

set (PROJECT_LINK_LIBS
    # LIST LINKER LIBS HERE
    D:/Downloads/NPU/4.0/Middlewares/ST/AI/Lib/GCC/ARMCortexM55/NetworkRuntime1200_CM55_GCC.a
    )

############ MODIFY ACCORDING TO REQUIREMENTS) ########################

#######################################################################

################## PROJECT SETUP ######################################
project(${PROJECT_NAME})
enable_language(ASM)

if (${PROJECT_TYPE} MATCHES ${PROJECT_TYPE_EXECUTABLE})
  add_executable(${PROJECT_NAME} ${PROJECT_SOURCES})
  add_custom_command(TARGET ${CMAKE_PROJECT_NAME} POST_BUILD COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${CMAKE_PROJECT_NAME}>)
  target_link_libraries(${PROJECT_NAME} ${PROJECT_LINK_LIBS})
elseif (${PROJECT_TYPE} MATCHES ${PROJECT_TYPE_STATIC_LIBRARY})
  add_library(${PROJECT_NAME} ${PROJECT_SOURCES})
endif()

add_compile_definitions (${PROJECT_DEFINES})
include_directories (${PROJECT_INCLUDES})

set (CMAKE_EXECUTABLE_SUFFIX ".elf")
set (CMAKE_STATIC_LIBRARY_SUFFIX ".a")
set (CMAKE_C_FLAGS "${MCPU} -std=gnu11 ${MFPU} ${MFLOAT_ABI} ${RUNTIME_LIBRARY} -mthumb -Wall -Werror -mcmse")
set (CMAKE_EXE_LINKER_FLAGS "-T${LINKER_SCRIPT} ${RUNTIME_LIBRARY_SYSCALLS} -Wl,-Map=test.map -Wl,--gc-sections -static -Wl,--start-group -lc -lm -lstdc++ -Wl,--end-group -Wl,-u,_printf_float")
set (CMAKE_ASM_FLAGS "${CMAKE_C_FLAGS} -x assembler-with-cpp")
