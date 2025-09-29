/* BMA16-Demo 3: Simultaneous execution of C program in FLASH (core 1) and ASM program in SRAM (Core 0) */

#include "pico/stdlib.h"
#include "pico/multicore.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>

extern uint8_t __my_asm_prgm_start__[];
extern uint8_t __my_asm_prgm_end__[];
extern uint8_t __flash_my_asm_prgm_load__[];
extern void asm_entry(void);

static void copy_my_asm_prgm(void) {
    size_t size = (size_t)(__my_asm_prgm_end__ - __my_asm_prgm_start__);
    uint8_t *dst = __my_asm_prgm_start__;
    uint8_t *src = __flash_my_asm_prgm_load__;
    /* use memcpy if you prefer; simple byte loop avoids potential linker optimizations issues */
    memcpy(dst, src, size);
}
// Core1 function (FLASH, normal C)
void core1_entry() {
    while (true) {
		printf("Currently running on core %i (C in FLASH) \n",get_core_num());		
        sleep_ms(2000);
    }
}

int main(void) {
    stdio_init_all();
    printf("C main starting...\n");
	printf("Currently running on core %i \n",get_core_num());
	multicore_launch_core1(core1_entry);
    // Copy .my_asm_prgm section from flash to SRAM
    copy_my_asm_prgm();

    printf("Copied my_asm_prgm: %p -> %p (%u bytes)\n",
           __flash_my_asm_prgm_load__,
           __my_asm_prgm_start__,
           (unsigned)(__my_asm_prgm_end__ - __my_asm_prgm_start__));

    // Now you can call your asm entry later
    void (*entry)(void) = (void (*)(void))((uintptr_t)asm_entry | 1);
    entry();  // never returns

    while (1) {
        tight_loop_contents();
    }
}

