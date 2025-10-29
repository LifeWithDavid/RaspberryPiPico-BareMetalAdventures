#   BMA17-Demo 5: This program builds on Demo 4, which has full duplex communications between the 
#   core 0 and core 1.  Demo 5 envokes USB communications where a tinyUSB "tud_task"
#   is periodically polled by the C program.  When a character is available, "tud_cdc_rx_cb()" 
#   acts as a callback to read the data.  This data is sent from the C program (Core 1) to the assembly
#   program (core 0) via the inter-core FIFO.  The assembly program operates on the data and
#   returns it to the C program (core 1), which then sends it back to the USB host terminal. 
#   Bit 31 is cleared for terminal host entry.  Bit 31 is set for control characters 
#   sent from the custom keyboard, which is handled differently.      
#

cmake_minimum_required(VERSION 3.19.8)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)

#This was originally F:\Users\pico\Downloads\pico assembly\first_asm_demo1
project(BMA17_Demo05 C CXX ASM
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
pico_enable_stdio_usb(${PROJECT_NAME} 1)
pico_enable_stdio_uart(${PROJECT_NAME} 0)
