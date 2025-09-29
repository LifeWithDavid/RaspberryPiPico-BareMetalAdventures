# BMA16-Demo 5: Startup program initiates execution of KB Display C program in FLASH on 
# Core 1, assembly program in SRAM on Core 0, and copies 64Kb data into SRAM. */#

cmake_minimum_required(VERSION 3.19.8)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)

#This was originally F:\Users\pico\Downloads\pico assembly\first_asm_demo1
project(05_prev_plus_C_handoff  C CXX ASM
)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PICO_EXAMPLES_PATH ${PROJECT_SOURCE_DIR})

# Initialize the SDK
pico_sdk_init()

# from F:\Users\pico assembly\BMA16_ASM_and_c\CMakeLists.txt
#pico_set_linker_script(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/memmap_staged.ld)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/emu_prog.o
   	COMMAND ${CMAKE_OBJCOPY} -I binary -O elf32-littlearm -B arm --rename-section .data=.emudata ${CMAKE_SOURCE_DIR}/emu_prog.prg ${CMAKE_BINARY_DIR}/emu_prog.o
	DEPENDS ${CMAKE_SOURCE_DIR}/emu_prog.prg
	COMMENT "Converting binary data to object file"
	)

add_custom_target(generate_binary_data ALL DEPENDS ${CMAKE_BINARY_DIR}/emu_prog.o)	

add_executable(${PROJECT_NAME}

	startup.c
	assembly.S
	emu_prog.o
	kbDisplayIntegrated.c
	kb_scan_decode.pio
)

add_dependencies(${PROJECT_NAME} generate_binary_data)

pico_set_linker_script(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/memmap_staged.ld)

#target_sources(AWG_1.pio PRIVATE AWG_1.c)
# Pull in our pico_stdlib which pulls in commonly used features
target_link_libraries(${PROJECT_NAME}
        pico_stdlib
		pico_multicore
        hardware_pio
		hardware_dma
        hardware_irq
		hardware_structs
		pico_stdlib hardware_i2c
        )

pico_generate_pio_header(${PROJECT_NAME} ${CMAKE_CURRENT_LIST_DIR}/kb_scan_decode.pio)

# create map/bin/hex file etc.
pico_add_extra_outputs(${PROJECT_NAME})

# Enable usb output, disable uart output
pico_enable_stdio_usb(${PROJECT_NAME} 0)
pico_enable_stdio_uart(${PROJECT_NAME} 1)
