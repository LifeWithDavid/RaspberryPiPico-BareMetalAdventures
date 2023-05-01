cmake_minimum_required(VERSION 3.19.8)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)


project(BMA03_demo4  C CXX ASM
)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PICO_EXAMPLES_PATH ${PROJECT_SOURCE_DIR})

# Initialize the SDK
pico_sdk_init()

add_executable(${PROJECT_NAME}

	main.c
	assembly.s
)



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
#pico_enable_stdio_usb(${PROJECT_NAME} 0)
#pico_enable_stdio_uart(${PROJECT_NAME} 1)



# add url via pico_set_program_url
#example_auto_set_url(blink2)


# Hardware-specific examples in subdirectories:
#add_subdirectory(adc)
#add_subdirectory(clocks)
#add_subdirectory(cmake)
#add_subdirectory(divider)
#add_subdirectory(dma)
#add_subdirectory(flash)
#add_subdirectory(gpio)
#add_subdirectory(i2c)
#add_subdirectory(interp)
#add_subdirectory(multicore)
#add_subdirectory(picoboard)
#add_subdirectory(pio)
#add_subdirectory(pwm)
#add_subdirectory(reset)
#add_subdirectory(rtc)
#add_subdirectory(spi)
#add_subdirectory(system)
#add_subdirectory(timer)
#add_subdirectory(uart)
#add_subdirectory(usb)
#add_subdirectory(watchdog)

