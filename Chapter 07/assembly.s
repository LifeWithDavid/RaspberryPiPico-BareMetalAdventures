//bare metal assembly PIO
//Life with David - BMA Chapter 07 - Demo 1 - PIO blink execution from RAMwith PLL clock

.cpu cortex-m0plus
.thumb

.word __reset_start__			// VMA for reset section
.word __data_end__				// VMA for end of SRAM 
.word __reset_load_start__		// LMA for reset section

.section .memcopy, "x"

start_memcpy:
	bl do_memcpy44
	ldr r0, =__reset_start__	// start of start1 VMA from linker
	ldr r1, =#1					// load "1" into reg 1 in order to...
	orr r0, r0, r1				// set bit 0 to tell "bx" to stay in THUMB mode
	bx r0						// now branch to "start1" and stay in THUMB mode
	b start_memcpy				// this is just a trap to make sure the BX above is working

do_memcpy44:           		// refer to 2.8.3.1.2. Fast Bulk Memory Fill / Copy Functions
    push {lr}
    ldr r0, =ROM_FN_TABLE      //0x00000014
    ldrh r0, [r0]
    ldr r2, =ROM_TABLE_LOOKUP  //0x00000018
    ldrh r2, [r2]					

    // Query the bootrom function pointer
    ldr r1, =0x3443 					// 'C','4' for _memcpy44
    blx r2

    //uint8_t *_memcpy44(uint32_t *dest, uint32_t *src, uint32_t n)
    mov r3, r0							// load memcopy function pointer into r3
    ldr r0, =__reset_start__        	// start of range to copy to
	ldr r2, =__data_end__				// end of range to copy to 
	sub r2, r2, r0						// number of bytes to copy (__data_end__ - __reset_start__) 
    ldr r1, =__reset_load_start__ 		// start of range to copy from
    blx r3								// call memcopy subroutine
    
    pop {pc}


memcopy_data:
.equ ROM_FN_TABLE,		0x00000014		// Pointer to a public function lookup table (rom_func_table) 
.equ ROM_TABLE_LOOKUP,	0x00000018		// Pointer to a helper function (rom_table_lookup())


.section .reset, "ax"

start1:

// Sets up the Crystal oscillator
	ldr r0, =xosc_base	// load xosc base address
	mov r1, #0xaa		// load 10101010 into r1 
	lsl r1, r1, #4		// and shift to 101010100000 
	str r1, [r0, #0]	// and store into XOSC:CNTL 2.16.7
	mov r1, #47			// load startup delay of "47" 2.16.3
	str r1, [r0, #0xc]	// and store in XOSC:STARTUP 2.17.7
// Start the XOSC
	ldr r0, =xosc_aset	// load in the xosc atomic set register base address
	ldr r1, =xosc_en	// load in xosc enable word 2.16.7
	str r1, [r0, #0]	// and store in the atomic set register for XOSC:CNTL 2.16.7
// Wait for the crystal to start up
	ldr r0, =xosc_base // load xosc base address
xosc_rdy:
	ldr r1, [r0, #0x04]	// load in XOSC:STATUS 2.16.7
	lsr r1, r1, #31		// and shift over 31 bits to isolate STABLE bit
	beq xosc_rdy		// if not stable, check again
// now the crystal oscillator is running, switch clock sources
	ldr r0, =clck_base // load in clock registers base address
	mov r1, #2			// selects the xosc for the ref clock 
	str r1, [r0, #0x30]	// save it in CLOCKS: CLK_REF_CTRL 2.15.7
	mov r1, #0			// selects the ref clock for the system clock 
	str r1, [r0, #0x3c]	// save it in CLOCKS: CLK_SYS_CTRL 2.15.7
	
// this selects the clock to output for CLK_GPOUT0 for debugging	
	mov r1, #0xa		// load in bits for selecting clk_ref for CLK_GPOUT0
						// 0x4-ROSC, 0x5-XOSC, 0x6-clk_sys, 0xa-clk_ref
	lsl r1, r1, #5		// move to bit 5
	str r1, [r0, #0x00]	//store in CLOCKS: CLK_GPOUT0_CTRL 2.15.7
	ldr r0, = clck_aset// load in clock atomic set register base
	mov r1, #1			// load in 1 bit
	lsl r1, r1, #11		// shift over 11 bits to enable CLOCKS: CLK_GPOUT0_CTRL
	str r1, [r0, #0x00]	// store clock enable bit in CLOCKS: CLK_GPOUT0_CTRL atomic set reg
	
// set up the PLL for xosc
// bring pll out of reset
//releases the peripheral reset for pll_sys
	ldr r0, =rst_clr	// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #1      	// load a 1 into bit 1
	lsl r1, r1, #12		// shift over 12 bits for pll_sys
	str r1, [r0, #0] 	// store the bitmask into the atomic register to clear register

// check if reset is done
pll_rst:     
    ldr r0, =rst_base	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #1			// load 1 in bit 1 of register 2 
	lsl r2, r2, #12		// shift over 12 bits for pll_sys
	and r1, r1, r2		// isolate bit 12
	beq pll_rst			// if bit 12 is 0 then check again, if not, reset is done
// now enable pll_sys
	ldr r0, =pll_sys_base
	mov r1, #125		// exact 125MHz lock at FBDIV=125, PD1=6, PD2=2, 2.18.2.1 
	str r1, [r0,#8]		// store in PLL: FBDIV_INT 2.18.4
	mov r1, #0x62			// PD1 = 6, PD2 = 2 
	lsl r1, r1, #12		// and shift over 12 bits
	str r1, [r0, #0x0c]	// store in PLL: PRIM 2.18.4
// power up the pll
	ldr r0, =pll_sys_aclr
	mov r1, #0x21		// clear PD, VCOPD in PLL: PWR
	str r1, [r0,#4]		// store in PLL: PWR 2.18.4
// wait for the pll to lock	
	ldr r0, =pll_sys_base
pll_lock:
	ldr r1, [r0, #0]	// load in the pll status register
	lsr r1, r1, #31		// isolate the "pll locked" bit 
	beq pll_lock		// if not locked, check again
// set the pll divisor here if desired

// now enable the pll_lock
	ldr r0, =pll_sys_aclr
	mov r1, #0x08		//clear POSTDIVPD in PLL: PWR to power up
	str r1, [r0, #4]
// now switch from ref clock to pll (pll is the aux source default)
	ldr r0, =clck_base
	mov r1, #1			// change to clksrc_clk_sys_aux in CLOCKS: CLK_SYS_CTRL 2.15.7
						// clksrc_pll_sys is the default for clksrc_clk_sys_aux
	str r1, [r0, #0x3c]	// store in CLOCKS: CLK_SYS_CTRL 2.15.7
		
//releases the peripheral reset for iobank_0
	ldr r0, =rst_clr	// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #32      	// load a 1 into bit 5
	str r1, [r0, #0] 	// store the bitmask into the atomic register to clear register

// check if iobank_0 reset is done
iob_rst:     
    ldr r0, =rst_base	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #32			// load 1 in bit 5 of register 2 (...0000000000100000)
	and r1, r1, r2		// isolate bit 5
	beq iob_rst			// if bit five is 0 then check again, if not, reset is done

enable_gpio25:
// set up GPIO 25	
	ldr r0, =ctrl_gp25
	mov r1, #5			// load function 5 for GPIO
	str r1, [r0]		// Store function_5 in GPIO25 control register 2.19.6.1
	
// Route xosc to gpout0 2.19.2 and 2.15.7 (CLK_GPOUT0_CTRL, GPIO21)
	ldr r0, =ctrl_gp21
	mov r1, #8			// function to tie CLK_GPOUT0_CTRL to GPIO21 2.19.2
	str r1, [r0]		// Store function_8 in GPIO21 control register 2.19.6.1

// releases the peripheral reset for pio_0
	ldr r0, =rst_clr	// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #1      	// load a 1 into bit 0
	lsl r1, r1, #10		// and shift over 10 bits
	str r1, [r0, #0] 	// store the bitmask into the atomic register to clear register

// check if pio_0 reset is done
pio_rst:     
    ldr r0, =rst_base	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #1      	// load a 1 into bit 0
	lsl r2, r2, #10		// and shift over 10 bits
	and r1, r1, r2		// isolate bit 10
	beq pio_rst			// if bit ten is 0 then check again, if not, reset is done	

load_pio_prog:
// load in the pio program "pio_prog"
	ldr r0, =pio_prog
	ldr r1, =pio0_prog_base
	mov r2, #16	// 16 words 

copy_loop:
	ldr r3, [r0]	// load word of program
	str  r3, [r1]	// Store it in Program register 
	add  r0, r0, #4	// increment data pointer to next word
	add  r1, r1, #4	// increment data memory to next register
	bl one_blink	// debug turn on LED GPIO25  blink for each word tranfer
	sub r2, r2, #1 	// decrement the instruction counter
	bne copy_loop	// if not zero, then go back and copy the next value
	
set_gpio04_base:	
// set base for set as GPIO04
	ldr r0, =pio0_base2
	ldr r1, =sm0_pinctl		// set base of gpio04
	str r1, [r0, #0x5c]		// store in sm0pinctrl

set_pio_output:
// set the control for pio output	
	ldr r0, =ctrl_gp04	// control register for GPIO04
	mov r1, #3			// load in 3 for output enable
	lsl r1, #12			// shift over 12 bits to sit in OEOVER, bits 12:13
	add r1, r1, #6		// add function 6 for FUNCSEL, bits 4:0 (0b00000000000000000011000000000110)
	str r1, [r0]  		// Store function_6 in GPIO04 control register (0x00003006)
	
set_up_pio:
// set up clock for PIO0, SM0
	ldr r0, =pio0_base2
	ldr r1, =sm0_clkdiv		// really slow clock
	str r1, [r0, #0x48]  	// store SM0_CLKDIV for slowest SM clock

set_top_wrap:
// set the top and bottom wrap 	
	ldr r0, =pio0_base2
	ldr r1, =sm0_execctrl  // set wrap top to 1f; no sticky
	str r1, [r0, #0x4c]		// store in sm0execctrl
	
enable_sm0:	
// restart pio0 state machine 0
	ldr r0, = pio0_base
	mov r1, #16				// restart SM0
	str r1, [r0, #0]		// store in cntl
	lsl r1, #4				// shift over 4 to restart the clock (0x100)
	str r1, [r0, #0]		// store in cntl
// force a jump to the beginning of the PIO program	
	ldr r0, =pio0_base2 	//
	ldr r1, =jmp_to_0		// load in forced jump to start of PIO program
	str r1, [r0, #0x58]		// store in SM0_INSTR

// enable the state machine	
	ldr r0, = pio0_base
	mov r1, #1			// enable SM0
	str r1, [r0, #0]	// store in cntl

// just waste time
waste_time:
	bl one_blink		// blink the on-board LED once	
	b waste_time		// and then do it OVER AND OVER AGAIN!
	
// ***********Troubleshooting Routines***************************

led_on:
	push {r5,r6,lr}		// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =sio_base  // SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #20]  	// 0x14 GPIO output value set
	pop {r5,r6,pc}		// return from subroutine
	
led_off:
	push {r5,r6,lr}		// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =sio_base 	// SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #24] 	// 0x18 GPIO output value clear
	pop {r5,r6,pc}		// return from subroutine

delay:
	push {r3, lr}
	ldr r3, =big_num	// load countdown number
delay_loop:
	sub r3, #1			// subtract 1 from register 3
	bne delay_loop		// loop back to delay if not zero
	pop {r3, pc}		// return from subroutine	
	
one_blink:				// will blink GPIO25 one short time
	push {lr}
	bl led_on		
	bl delay
	bl delay
	bl led_off
	bl delay
	bl delay
	pop {pc}
	
two_blinks:			// will blink GPIO25 two short times
	push {lr}
	bl led_on		
	bl delay
	bl led_off
	bl delay
	bl led_on		
	bl delay
	bl led_off
	bl delay
	bl delay
	bl delay
	pop {pc}
	
long_blink:			// will blink GPIO25 one long
	push {lr}
	bl led_on		
	bl delay
	bl delay
	bl delay
	bl delay
	bl delay
	bl delay
	bl delay
	bl delay
	bl led_off
	bl delay
	bl delay
	pop {pc}
	
// compare memory locations between __reset_load_start__ and __reset_start__
// r0-Start of memory range 1, r1-start of memeory range 2, 
compare_mem: 
	push {r0,r1,r2,r3,r4,lr}
	ldr r0, =__reset_start__
	ldr r1, =__reset_load_start__
	mov r2, #0x8					// number of words to check
compare_loop:	
	ldr r3, [r0, #0]				// load in ram word
	ldr r4, [r1, #0]				// load in flash word
	cmp r4, r3						// compare the two
	bne bypass_blink				// if not equal, then bypass blink
	bl one_blink
bypass_blink:	
	add r0, r0, #4					// increment ram location by 1 word
	add r1, r1, #4					// increment flash location by 1 word
	sub r2, #1						// decrement word
	bne compare_loop
	pop {r0,r1,r2,r3,r4,pc}

	nop								// 2 byte pad to align data section
pio_prog:
.word 0x0000ff01 	// 00 	set(pins,1) 	[31] ; turns on set pin 0
.word 0x0000bf42	// 01	nop				[31] ; waste time
.word 0x0000bf42	// 02	nop				[31] ; waste time
.word 0x0000bf42	// 03	nop				[31] ; waste time
.word 0x0000bf42	// 04	nop				[31] ; waste time
.word 0x0000bf42	// 05	nop				[31] ; waste time
.word 0x0000bf42	// 06	nop				[31] ; waste time
.word 0x0000bf42	// 07	nop				[31] ; waste time
.word 0x0000ff00	// 08	set(pins,0) 	[31] ; turns off set pin 0
.word 0x0000bf42	// 09	nop				[31] ; waste time
.word 0x0000bf42	// 10	nop				[31] ; waste time
.word 0x0000bf42	// 11	nop				[31] ; waste time
.word 0x0000bf42	// 12	nop				[31] ; waste time
.word 0x0000bf42	// 13	nop				[31] ; waste time
.word 0x0000bf42	// 14	nop				[31] ; waste time
.word 0x00001f00	// 15	jmp(mainloop:)	[31] ; jumps to beginning of program
.word 0x00000000	// pad

defined_data:	
.equ rosc_freq,	0x00fabfa0	// base for rosc frequency range, add 4 through 8
.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
.equ rst_base, 	0x4000c000	// reset controller base 2.14.3
.equ ctrl_gp04,	0x40014024	// GPIO04_CTRL 2.19.6.1
.equ ctrl_gp21,	0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ ctrl_gp25,	0x400140cc	// GPIO25_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ clck_base,	0x40008000	// Clock register base address
.equ clck_aset,	0x4000a000	// Clock atomic set
.equ pll_sys_base,	0x40028000	// PLL system registers base address
.equ pll_sys_aclr,	0x4002b000	//  PLL system atomic clear base address
.equ rosc_base,	0x40060000	// Ring oscillator base 2.17.8
.equ rosc_aset,	0x40062000	// Ring oscillator atomic set register
.equ xosc_base,	0x40024000	// XOSC Base address
.equ xosc_aset,	0x40026000	// XOSC atomic set
.equ xosc_en,	0x00fab000	// enable for xosc
.equ rosc_pw, 	0x96960000	// ring oscillator password 2.17.8
.equ rosc_powr,	0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
.equ sio_base, 	0xd0000000	// SIO base 2.3.1.7
.equ big_num, 	0x00780000	// large number for the delay loop
.equ pio0_prog_base,	0x50200048	// start of the pio0 program memory
.equ pio0_base, 	0x50200000	// start of the PIO0 registers
.equ pio0_base2,	0x50200080 // start of second half of PIO0 registers
.equ pio0_aset, 	0x50202000	// start of atomic set for PIO0 registers
.equ pio0_aset2, 	0x50202080 // start of second half of PIO0 atomic registers
.equ sm0_pinctl,	0x0c000080 // setting gpio4 and 1 pins for set sm0pinctrl
.equ sm0_execctrl,	0x0001f000 // no sticky, 0x1f top wrap, 0x0 bottom wrap, 
.equ sm0_clkdiv, 	0xffff0000	// really slow state machine 0 clock 
.equ jmp_to_0,		0x00000000	// jmp 0


