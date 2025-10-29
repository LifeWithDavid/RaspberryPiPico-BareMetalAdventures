/* BMA16-Demo 5: Startup program initiates execution of KB Display C program in FLASH on 
   Core 1, assembly program in SRAM on Core 0, and copies 64Kb data into SRAM. */
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/irq.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>

__attribute__((noreturn))
void main_program(void);

extern uint8_t __my_asm_prgm_start__[];
extern uint8_t __my_asm_prgm_end__[];
extern uint8_t __flash_my_asm_prgm_load__[];
extern uint8_t __emu_load_start__[];
extern uint8_t __emu_start__[];
extern uint8_t __emu_end__[];
extern void asm_entry(void);
extern void sio_irq_handler(void);  // assembly ISR




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
	printf("startup.c handing over control to kbDisplayIntegrated, currently running on core %i (C in FLASH) \n",get_core_num());
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

    printf("C main starting...\n");
	printf("Currently running on core %i \n",get_core_num());
	
	multicore_launch_core1(core1_entry);
    // Copy .my_asm_prgm section from flash to SRAM
    copy_my_asm_prgm();

    printf("Copied my_asm_prgm: %p -> %p (%u bytes) using core %i \n",
           __flash_my_asm_prgm_load__,
           __my_asm_prgm_start__,
           (unsigned)(__my_asm_prgm_end__ - __my_asm_prgm_start__),get_core_num());

	copy_ram_emu_data();

    printf("Copied emu_data: %p -> %p (%u bytes) using core %i \n",
           __emu_load_start__,
           __emu_start__,
           (unsigned)(__emu_end__ - __emu_start__),get_core_num());		   
	init_sio_irq();  //added to initialize for interrupt
    // Now you can call your asm entry later
    void (*entry)(void) = (void (*)(void))((uintptr_t)asm_entry | 1);
    entry();  // never returns

    while (1) {
        tight_loop_contents();
    }
}

