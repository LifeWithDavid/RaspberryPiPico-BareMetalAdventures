# BMA16-Demo 3: Simultaneous execution of C program in FLASH (core 1) and ASM program in SRAM (Core 0)
cmake_minimum_required(VERSION 3.19.8)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)

#This was originally F:\Users\pico\Downloads\pico assembly\first_asm_demo1
project(03_dual_core  C CXX ASM
)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PICO_EXAMPLES_PATH ${PROJECT_SOURCE_DIR})

# Initialize the SDK
pico_sdk_init()

add_executable(${PROJECT_NAME}

	main.c
	assembly.S
)

# from F:\Users\pico assembly\BMA16_ASM_and_c\CMakeLists.txt
pico_set_linker_script(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/memmap_staged.ld)

#target_sources(AWG_1.pio PRIVATE AWG_1.c)
# Pull in our pico_stdlib which pulls in commonly used features
target_link_libraries(${PROJECT_NAME}
        pico_stdlib
		pico_multicore
        #hardware_pio
		#hardware_dma
        #hardware_irq
		#hardware_structs
        )

# create map/bin/hex file etc.
pico_add_extra_outputs(${PROJECT_NAME})

# Enable usb output, disable uart output
pico_enable_stdio_usb(${PROJECT_NAME} 0)
pico_enable_stdio_uart(${PROJECT_NAME} 1)

