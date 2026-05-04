/* 
#   BMA18-final: This is the emulator running on core 0 and the kbDisplayIntegrated running 
#   on core 1.  ASCII communications is by the Pico's USB port.  The emulator outputs 
#   through the kbDisplay program using two global variable, core0to1_flags, and core0to1_value 
#   and receives input through the intercore FIFO from kbDisplayIntegrated. 
#   Emulator status registers are stored in 5 variables in X scratch on every pass. The C program
#   retrieves those values as needed using structs.  The blinken lights display is expanded to 
#   include all registers.  Control functions are added.
   */
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/irq.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "hardware/uart.h"

#define UART_ID uart0
#define BAUD_RATE 115200
#define UART_TX_PIN 0
#define UART_RX_PIN 1

__attribute__((noreturn))
void main_program(void);

extern uint8_t 	__my_asm_prgm_start__[];
extern uint8_t 	__my_asm_prgm_end__[];
extern uint8_t 	__flash_my_asm_prgm_load__[];
extern uint8_t 	__emu_load_start__[];
extern uint8_t 	__emu_start__[];
extern uint8_t 	__emu_end__[];
extern void 	asm_entry(void);
extern void 	sio_irq_handler(void);  // assembly ISR
extern volatile uint32_t pendingFunction;

//Copy over the asm program to SRAM
static void copy_my_asm_prgm(void) {
    size_t size = (size_t)(__my_asm_prgm_end__ - __my_asm_prgm_start__);
    uint8_t *dst = __my_asm_prgm_start__;
    uint8_t *src = __flash_my_asm_prgm_load__;
    /* use memcpy if you prefer; simple byte loop avoids potential linker optimizations issues */
    memcpy(dst, src, size);
}

//Copy over the emu binary data to emu_ram (0x20020000)
static void copy_ram_emu_data(void) {
    size_t size = (size_t)(__emu_end__ - __emu_start__);
    uint8_t *dst = __emu_start__;
    uint8_t *src = __emu_load_start__;
    /* use memcpy if you prefer; simple byte loop avoids potential linker optimizations issues */
    memcpy(dst, src, size);
}
// Core1 function (FLASH, normal C)
void core1_entry() {
	main_program();
    while (true) {
		printf("oh,oh, still stuck in startup.c, currently running on core %i (C in FLASH) \n",get_core_num());		
        sleep_ms(2000);
    }
}

void init_sio_irq() {   //added to initialize for interrupt
    irq_set_exclusive_handler(SIO_IRQ_PROC0, sio_irq_handler);
    irq_set_enabled(SIO_IRQ_PROC0, true);	
}

int main(void) {
	
    stdio_init_all();	
	sleep_ms(10000);  //delay for 10 seconds to get USB/puTTY started
	multicore_launch_core1(core1_entry);  // starts the keyboard display program in core 1
    // Copy .my_asm_prgm section from flash to SRAM
    copy_my_asm_prgm();  // this copies the assembly program into SRAM
	copy_ram_emu_data(); // this copies the emulator memory into SRAM
	init_sio_irq();  //added to initialize for interrupt
	sleep_ms(1000);  //delay for 1 seconds to insure kbDisplay starts first
    void (*entry)(void) = (void (*)(void))((uintptr_t)asm_entry | 1);
    entry();  // transfer execution to the assembly program in core 0 and never return

    while (1) {
        tight_loop_contents(); //trap in case everything goes south
    }
}

