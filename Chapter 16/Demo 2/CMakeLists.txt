# BMA16-Demo 2: Transfer execution from C program in FLASH to ASM program in SRAM 
cmake_minimum_required(VERSION 3.19.8)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)

#This was originally F:\Users\pico\Downloads\pico assembly\first_asm_demo1
project(02_c_fl_asm_ram  C CXX ASM
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

