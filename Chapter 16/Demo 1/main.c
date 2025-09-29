//BMA16-Demo 1: Transfer execution from C program in FLASH to ASM program in FLASH

#include "pico/stdlib.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>

extern uint8_t __my_asm_prgm_start__[];
extern uint8_t __my_asm_prgm_end__[];
extern void asm_entry(void);


int main(void) {
    stdio_init_all();
    printf("C main starting...\n");


    // This calls the assembly program 
    void (*entry)(void) = (void (*)(void))((uintptr_t)asm_entry | 1);
    entry();  // never returns

    while (1) {
        tight_loop_contents();
    }
}