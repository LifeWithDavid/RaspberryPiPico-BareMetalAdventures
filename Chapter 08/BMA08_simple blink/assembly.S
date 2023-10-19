//bare metal assembly PIO
//Life with David - BMA Chapter 08 - Demo 1 - PIO blink execution from RAM with PLL clock
//   and UART communications

.cpu cortex-m0plus
.thumb
.section .reset, "awx"

.word __main_start__		// VMA for reset section
.word __data_end__			// VMA for end of SRAM 
.word __main_load_start__	// LMA for reset section

start1:

// Sets up the Crystal oscillator
	ldr r0, =xosc_base		// load xosc base address
	mov r1, #0xaa			// load 10101010 into r1 
	lsl r1, r1, #4			// and shift to 101010100000 
	str r1, [r0, #0]		// and store into XOSC:CNTL 2.16.7
	mov r1, #47				// load startup delay of "47" 2.16.3
	str r1, [r0, #0xc]		// and store in XOSC:STARTUP 2.17.7
// Start the XOSC
	ldr r0, =xosc_aset		// load in the xosc atomic set register base address
	ldr r1, =xosc_en		// load in xosc enable word 2.16.7
	str r1, [r0, #0]		// and store in the atomic set register for XOSC:CNTL 2.16.7
// Wait for the crystal to start up
	ldr r0, =xosc_base 		// load xosc base address
xosc_rdy:
	ldr r1, [r0, #0x04]		// load in XOSC:STATUS 2.16.7
	lsr r1, r1, #31			// and shift over 31 bits to isolate STABLE bit
	beq xosc_rdy			// if not stable, check again
// now the crystal oscillator is running, switch clock sources
	ldr r0, =clck_base 		// load in clock registers base address
	mov r1, #2				// selects the xosc for the ref clock 
	str r1, [r0, #0x30]		// save it in CLOCKS: CLK_REF_CTRL 2.15.7
	mov r1, #0				// selects the ref clock for the system clock 
	str r1, [r0, #0x3c]		// save it in CLOCKS: CLK_SYS_CTRL 2.15.7
	
// this selects the clock to output for CLK_GPOUT0 for debugging	
	mov r1, #0xa			// load in bits for selecting clk_ref for CLK_GPOUT0
							// 0x4-ROSC, 0x5-XOSC, 0x6-clk_sys, 0xa-clk_ref
	lsl r1, r1, #5			// move to bit 5
	str r1, [r0, #0x00]		//store in CLOCKS: CLK_GPOUT0_CTRL 2.15.7
	ldr r0, = clck_aset	// load in clock atomic set register base
	mov r1, #1				// load in 1 bit
	lsl r1, r1, #11			// shift over 11 bits to enable CLOCKS: CLK_GPOUT0_CTRL
	str r1, [r0, #0x00]		// store clock enable bit in CLOCKS: CLK_GPOUT0_CTRL atomic set reg

// ***************Set up PLL**************************	
// set up the PLL for xosc
// bring pll out of reset
//releases the peripheral reset for pll_sys
	ldr r0, =rst_clr		// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #1      		// load a 1 into bit 1
	lsl r1, r1, #12			// shift over 12 bits for pll_sys
	str r1, [r0, #0] 		// store the bitmask into the atomic register to clear register

// check if reset is done
pll_rst:     
    ldr r0, =rst_base		// base address for reset controller
	ldr r1, [r0, #8] 		// offset to get to the reset_done register
	mov r2, #1				// load 1 in bit 1 of register 2 
	lsl r2, r2, #12			// shift over 12 bits for pll_sys
	and r1, r1, r2			// isolate bit 12
	beq pll_rst			// if bit 12 is 0 then check again, if not, reset is done
// now enable pll_sys
	ldr r0, =pll_sys_base
	mov r1, #125			// exact 125MHz lock at FBDIV=125, PD1=6, PD2=2, 2.18.2.1 
	str r1, [r0,#8]			// store in PLL: FBDIV_INT 2.18.4
	mov r1, #0x62			// PD1 = 6, PD2 = 2 
	lsl r1, r1, #12			// and shift over 12 bits
	str r1, [r0, #0x0c]		// store in PLL: PRIM 2.18.4
// power up the pll
	ldr r0, =pll_sys_aclr
	mov r1, #0x21			// clear PD, VCOPD in PLL: PWR
	str r1, [r0,#4]			// store in PLL: PWR 2.18.4
// wait for the pll to lock	
	ldr r0, =pll_sys_base
pll_lock:
	ldr r1, [r0, #0]		// load in the pll status register
	lsr r1, r1, #31			// isolate the "pll locked" bit 
	beq pll_lock			// if not locked, check again
// set the pll divisor here if desired

// now enable the pll_lock
	ldr r0, =pll_sys_aclr
	mov r1, #0x08			//clear POSTDIVPD in PLL: PWR to power up
	str r1, [r0, #4]
// now switch from ref clock to pll (pll is the aux source default)
	ldr r0, =clck_base
	mov r1, #1				// change to clksrc_clk_sys_aux in CLOCKS: CLK_SYS_CTRL 2.15.7
							// clksrc_pll_sys is the default for clksrc_clk_sys_aux
	str r1, [r0, #0x3c]		// store in CLOCKS: CLK_SYS_CTRL 2.15.7
	
// ************************peripheral reset ***********************	
		
//releases the peripheral reset for iobank_0
	ldr r0, =rst_clr		// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #32      		// load a 1 into bit 5
	str r1, [r0, #0] 		// store the bitmask into the atomic register to clear register

// check if iobank_0 reset is done
iob_rst:     
    ldr r0, =rst_base		// base address for reset controller
	ldr r1, [r0, #8] 		// offset to get to the reset_done register
	mov r2, #32				// load 1 in bit 5 of register 2 (...0000000000100000)
	and r1, r1, r2			// isolate bit 5
	beq iob_rst				// if bit five is 0 then check again, if not, reset is done

enable_gpio25:
// set up GPIO 25	
	ldr r0, =ctrl_gp25
	mov r1, #5				// load function 5 for GPIO
	str r1, [r0]			// Store function_5 in GPIO25 control register 2.19.6.1

// Route xosc to gpout0 2.19.2 and 2.15.7 (CLK_GPOUT0_CTRL, GPIO21)
	ldr r0, =ctrl_gp21
	mov r1, #8				// function to tie CLK_GPOUT0_CTRL to GPIO21 2.19.2
	str r1, [r0]			// Store function_8 in GPIO21 control register 2.19.6.1
	


// checks if xosc is stable
xosc_stable:
	ldr r0, =xosc_rw	  	// base for xosc clock 
	ldr r1, [r0, #0x04]	  	// load xosc status XOSC: STATUS offset 4
	lsr r1, #31			  	// get rid of all bits but xosc stable
	beq xosc_stable	  	// if not stable then check again

// connect the xosc to GPIO 21 so we can measure its frequency "Function 8" 2.19.2
config_gpout0:
	ldr r0, =clck_base   	// Base for clocks register
	mov r1, #0x45 	  		// load in 0b1000101 to enable and select xosc
	lsl r1, r1, #5	  		// shift over 5 bits to enable the clock generator
	str r1, [r0,#0]		  	// store in CLK_GPOUT0_CTRL (...100010100000)	
	ldr r0, =iob0a_rw	  	// base address iobank_0a 0x40014080	2.19.6.1
	mov r1, #8			  	// function 8 CLOCK GPOUT0        	2.19.2
	str r1, [r0, #0x2c]	  	// store function 8 in GPIO21_CTRL  	2.19.6.1
	
// ******************************initalize UART 0***********
// This sets up the UART to communicate	

//Set peripheral clock 2.15.7-do after xosc started and before UART brought out of reset
set_peri_clk:
	ldr r0, =clck_base   		// Base for clocks register
	mov r1, #1 		  		// load in first bit
	lsl r1, r1, #11	  		// shift over 11 bits to enable the clock generator
	add r1, #128	  		// add 0b10000000 to select the crystal ocsillator
	str r1, [r0,#0x48]    	// store in clk_peri_ctrl (...100010000000)	

// First reset the uart
reset_uart:
	ldr r0, =rst_set	  	//atomic register for clearing reset controller (0x4000c000+0x2000)
	mov r1, #1			  	//load 1 into bit 0
	lsl r1, r1, #22	  		//shift bit over to align with bit 22, UART0
	str r1, [r0,#0]	  		//store the bitmask into the atomic register to assert UART0 reset	
	

// Bring UART0 out of reset (deassert the reset)
deassert_uart_reset:  
	ldr r0, =rst_clr  		//atomic register for clearing reset controller (0x4000c000+0x3000)
	mov r1, #1		  		//load 1 into bit 0
	lsl r1, r1, #22	  		//shift bit over to align with bit 22, UART0
	str r1, [r0,#0]	  		//store the bitmask into the atomic register to deassert UART0 reset

// check if UART0 reset is deasserted

uartrst:     
	ldr r0, =rst_base	  	// base address for reset controller
	ldr r1, [r0, #8] 		// offset to get to the reset_done register
	mov r2, #1				// load 1 in bit 1 of register 2 
	lsl r2, r2, #22			// shift over 22 bits for UART0
	and r1, r1, r2			// isolate bit 22
	beq uartrst   		// if bit 22 is 0 then check again, if not, reset is done
	nop	

// Enable UART receive and transmit and then enable uart 4.2.8 UARTCR 0b1100000001
enable_uart:
	ldr r0, =uart0_rw  	// uart0 register base address 4.2.8
	mov r1, #3				// move 0b11 for 8 bit word UARTCR: RXE and TXE 
	lsl r1, #8				// and shift it over to bits 8 and 9
	add r1, #0x01			// add bit for enable UARTCR: UARTEN
	str r1, [r0, #0x030]   	// store in UARTCR register
	
// set baud rate of UART0  4.2.7.1
// Required Baud Rate: 115200; UARTCLK: 12MHz 2.16.1
// (12*10^6)/(16*115200)~=6.5104; BRDI=6, BRDF=0.5104, m=integer((0.514*64)+0.5)=33
set_baud_rate:

	mov r1, #6	  			// integer baud rate
	str r1, [r0, #0x024]  	// store in integer baud rate register UARTIBRD 4.2.8
	mov r1, #33			  	// fractional Baud Rate
	str r1, [r0, #0x028]  	// store in fractional baud rate register, UARTFBRD 4.2.8
	
// set word length (8 bits) and enable FIFOs UARTLCR_H 4.2.8
set_word_len:
	mov r1, #112			// 0b01110000 = 112 (UARTLCR_H) (112: fifos enabled, 111: fifos disabled)
	str r1, [r0, #0x02c]  	// store in UARTLCR_H
	
// Connect UART0 on iobank_0 pads 0 and 1 using "Function 2"   2.19.2
config_uart_gpio:
	ldr r0, =iob0_rw	  	//base address iobank_0 			2.19.6.1
	mov r1, #2			  	// function 2 UART0_TX & UART0_RX  2.19.2
	str r1, [r0, #4]  		//store function 2 in GPIO0_CTRL  2.19.6.1
	str r1, [r0, #0x0c]    //store function 2 in GPIO1_CTRL  2.19.6.1	

// **************init PIO 0 *******************************

// releases the peripheral reset for pio_0
	ldr r0, =rst_clr		// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #1      		// load a 1 into bit 0
	lsl r1, r1, #10			// and shift over 10 bits
	str r1, [r0, #0] 		// store the bitmask into the atomic register to clear register

// check if pio_0 reset is done
pio_rst:     
    ldr r0, =rst_base		// base address for reset controller
	ldr r1, [r0, #8] 		// offset to get to the reset_done register
	mov r2, #1      		// load a 1 into bit 0
	lsl r2, r2, #10			// and shift over 10 bits
	and r1, r1, r2			// isolate bit 10
	beq pio_rst			// if bit ten is 0 then check again, if not, reset is done

start_memcpy:
	bl do_memcpy44
	ldr r0, =__main_start__	// start of start1 VMA from linker
	ldr r1, =#1				// load "1" into reg 1 in order to...
	orr r0, r0, r1			// set bit 0 to tell "bx" to stay in THUMB mode
	bx r0					// now branch to "start1" and stay in THUMB mode
	b start_memcpy		// this is just a trap to make sure the BX above is working

do_memcpy44:           	// refer to 2.8.3.1.2. Fast Bulk Memory Fill / Copy Functions
    push {lr}
    ldr r0, =ROM_FN_TBL   //0x00000014
    ldrh r0, [r0]
    ldr r2, =ROM_TBL_PNT	//0x00000018
    ldrh r2, [r2]					

    // Query the bootrom function pointer
    ldr r1, =0x3443 		// 'C','4' for _memcpy44
    blx r2

    //uint8_t *_memcpy44(uint32_t *dest, uint32_t *src, uint32_t n)
    mov r3, r0							// load memcopy function pointer into r3
    ldr r0, =__main_start__        	// start of range to copy to
	ldr r2, =__data_end__				// end of range to copy to 
	sub r2, r2, r0						// number of bytes to copy (__data_end__ - __reset_start__) 
    ldr r1, =__main_load_start__ 		// start of range to copy from
    blx r3								// call memcopy subroutine
    pop {pc}
	
.align 4
.section .resetdata, "a"

reset_data:
.equ ROM_FN_TBL,	0x00000014	// Pointer to a public function lookup table (rom_func_table) 
.equ ROM_TBL_PNT,	0x00000018	// Pointer to a helper function (ROM_TBL_PNT())	
.equ rosc_freq,	0x00fabfa0	// base for rosc frequency range, add 4 through 8
.equ clck_base,	0x40008000	// Clock register base address
.equ clck_aset,	0x4000a000	// Clock atomic set
.equ rst_base, 	0x4000c000	// reset controller base 2.14.3
.equ rst_set, 		0x4000e000 	// atomic register for setting reset controller 2.1.2
.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
.equ iob0_rw, 		0x40014000	// iobank_0 base address 2.19.6.1
.equ iob0a_rw,		0x40014080 	// iobank_0 base address starting at GPIO16 2.19.6.1
.equ ctrl_gp04,	0x40014024	// GPIO04_CTRL 2.19.6.1
.equ ctrl_gp21,	0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ ctrl_gp25,	0x400140cc	// GPIO25_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ xosc_rw, 		0x40024000 	// Base for xosc 2.16.7
.equ pll_sys_base,	0x40028000	// PLL system registers base address
.equ pll_sys_aclr,	0x4002b000	//  PLL system atomic clear base address
.equ uart0_rw,		0x40034000	// UART0 register base address 4.2.8
.equ rosc_base,	0x40060000	// Ring oscillator base 2.17.8
.equ rosc_aset,	0x40062000	// Ring oscillator atomic set register
.equ xosc_base,	0x40024000	// XOSC Base address
.equ xosc_aset,	0x40026000	// XOSC atomic set
.equ xosc_en,		0x00fab000	// enable for xosc
.equ rosc_pw, 		0x96960000	// ring oscillator password 2.17.8
.equ rosc_powr,	0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
.equ sio_base, 	0xd0000000	// SIO base 2.3.1.7
.equ big_num, 		0x00780000	// large number for the delay loop
.equ nvic_enable, 0xe000e100	// set interrupt enable


.section .main, "ax"

stage_1:
	ldr r0, =pio_prog 

stage_2:	
	ldr r1, =pio0_prog_base

stage_3:	
	ldr r0, =pio0_base2
	bl stage_3
// You'll never get here
	bl led_on	
































load_pio_prog:
// load in the pio program "pio_prog"
	ldr r0, =pio_prog
	bl prt_cr_lf
	bl reg_prt
	ldr r1, =pio0_prog_base
	mov r2, #16	// 16 words


copy_loop:
	ldr r3, [r0]		// load word of program
	str  r3, [r1]		// Store it in Program register 
	add  r0, r0, #4		// increment data pointer to next word
	add  r1, r1, #4		// increment data memory to next register
	bl one_blink		// debug turn on LED GPIO25  blink for each word tranfer
	sub r2, r2, #1 		// decrement the instruction counter
	bne copy_loop		// if not zero, then go back and copy the next value
	
	
set_gpio04_base:	
// set base for set as GPIO04
	ldr r0, =pio0_base2
	bl prt_spc
	bl reg_prt
	ldr r1, =sm0_pinctl	// set base of gpio04
	str r1, [r0, #0x5c]		// store in sm0pinctrl

set_pio_output:
// set the control for pio output	
	ldr r0, =ctrl_gp04	// control register for GPIO04
	mov r1, #3				// load in 3 for output enable
	lsl r1, #12				// shift over 12 bits to sit in OEOVER, bits 12:13
	add r1, r1, #6			// add function 6 for FUNCSEL, bits 4:0 (0b00000000000000000011000000000110)
	str r1, [r0]  			// Store function_6 in GPIO04 control register (0x00003006)
	
set_up_pio:
// set up clock for PIO0, SM0
	ldr r0, =pio0_base2
	ldr r1, =sm0_clkdiv	// really slow clock
	str r1, [r0, #0x48]  	// store SM0_CLKDIV for slowest SM clock

set_top_wrap:
// set the top and bottom wrap 	
	ldr r0, =pio0_base2
	ldr r1, =sm0_execctrl	// set wrap top to 1f; no sticky
	str r1, [r0, #0x4c]		// store in sm0execctrl
	bl long_blink			// long blink to verify bottom wrap set
	
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
	mov r1, #1				// enable SM0
	str r1, [r0, #0]		// store in cntl
	bl two_blinks			// two blinks to verify state machine enabled

// ************************UART communications *****************************
// Memory examination loop - type in memory location (hex) and will print mem value
mem_exam_loop:
	bl prt_cr_lf			// new line
	bl ascii2hex			// convert 8 ascii characters to 32 bit word
	mov r0, r1				// move binary word into R0
	bl prt_cr_lf			// new line 
	bl reg_prt				// echo the memory address 
	bl prt_spc				// print a space
	ldr r0, [r1, #0]		// grab the memory value of the word address in R1
	bl reg_prt				// print the memory value
	b mem_exam_loop		// do it all again

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
	
// compare memory locations between __main_load_start__ and __main_start__
// r0-Start of memory range 1, r1-start of memeory range 2, 
compare_mem: 
	push {r0,r1,r2,r3,r4,lr}
	ldr r0, =__main_start__
	ldr r1, =__main_load_start__
	mov r2, #0x8			// number of words to check
compare_loop:	
	ldr r3, [r0, #0]		// load in ram word
	ldr r4, [r1, #0]		// load in flash word
	cmp r4, r3				// compare the two
	bne bypass_blink		// if not equal, then bypass blink
	bl one_blink
bypass_blink:	
	add r0, r0, #4			// increment ram location by 1 word
	add r1, r1, #4			// increment flash location by 1 word
	sub r2, #1				// decrement word
	bne compare_loop
	pop {r0,r1,r2,r3,r4,pc}
	
reg_prt:
	push {r0,r1,r4,r5,lr}
	mov r4, r0				// stash untouched register word into r4
	mov r5, #32				// number of bits per register

reg_prt_0:
	sub r5, #4				// calculate the number of bits to shift
	mov r0, r4 				// refresh r0 with original word
	lsr r0, r5				// shift to get desired nibble into 4 lsbits
	mov r1, #15				// bit mask for 4 LSBits
	and r0, r1				// isolate 4 LSBits
	cmp r0, #9				// is it a number?
	bhi reg_prt_1			// if not, make it a letter (a-f)
	add r0, #48				// convert number to ascii
	b reg_prt_2			// branch to ascii out
reg_prt_1:				
	add r0, #87				// convert to a letter
reg_prt_2:
	bl uart0_out			// output the character
	cmp r5, #0				// are we done?
	bne reg_prt_0			// if not, do it again
	pop {r0,r1,r4,r5,pc}	// if done, then return
	
prt_spc:
	push {r0, lr}
	mov r0, #0x20			// load in a "space"
	bl uart0_out			// and print it out
	pop {r0, pc}
	
prt_cr_lf:
	push {r0, lr}
	mov r0, #0x0d			// load in a "carrage return
	bl uart0_out			// and print it out
	mov r0, #0x0a			// load in a "line feed"
	bl uart0_out			// and print it out
	pop {r0, pc}


uart0_out:				// data out in r0
	push {r0,r1,r2,r3,lr}
	
uart0_out_loop:		
	ldr r1, =uart0_rw 		// base address for uart0 registers
	ldr r2, [r1, #0x18]		// read UART0 flag register UARTFR 4.2.8
	mov r3, #32				// mask for bit 5, TX FIFO full TXFF
	and r2, r3				// isolate bit 5
	bne uart0_out_loop	// if TX FIFO is full, go back and check again
	mov r2, #0xff			// bit mask for the 8 lowest bits
	and r0, r2				// get rid of all but the lowest 8 bits of data
	str r0, [r1, #0]		// store data in uart data register, UARTDR
	pop {r0,r1,r2,r3,pc}	// return
	
uart0_in:
	push {r1,r2,r3,lr}
uart0_in_loop:	
	ldr r1, =uart0_rw 	 	// base address for uart0 registers
	ldr r2, [r1, #0x18] 	// read UART0 flag register UARTFR 4.2.8
	mov r3, #16		 		// mask for bit 4, RX FIFO empty RXFE
	and r2, r3		 		// isolate bit 4
	bne uart0_in_loop	// if RX FIFO is empty, go back and check again
	ldr r0, [r1, #0] 		// load data from uart data register into r0, UARTDR
	pop {r1,r2,r3,pc}		//return
	
echo_in:
	push {lr}
	bl uart0_in			// get a character
	bl uart0_out			// and echo it out
	pop {pc}				// and return
// ****************ascii to hex ***********************

ascii2hex:				// converts ascii input into a binary word
	push {r0, r2, r3, lr}
	mov r2, #8				// number of hex characters (nibbles) expected
	mov r1, #0				// clear r1 to accept built binary character
ascii2hex_loop:	
	bl uart0_in			// get ascii character in r0
	mov r3, r0 				// memorialize the original character
	cmp r0, #0x30			// could character be a letter or number?
	blo ascii2hex_loop	// no, go back and get another ascii character
	cmp r0, #0x39			// could character be a number?
	bhi ascii2hex_0		// no. see if it a letter a-f
	sub r0, r0, #0x30		// it's a number so convert it to a nibble (0x0 to 0x9)
	b ascii2hex_1			// branch to building the word
ascii2hex_0:
	cmp r0, #0x61			// could character be a letter?
	blo ascii2hex_loop	// no, go back and get another character
	cmp r0, #0x66			// character is a letter, could it be a-f?
	bhi ascii2hex_loop	// no, go back and get another character
	sub r0, r0, #0x57		// it is a-f, convert to a nibble
ascii2hex_1:
	add r1, r1, r0			// add the converted digit to the lsbyte the word
	sub r2, r2, #1			// decrement the number of nibbles expected
	beq ascii2hex_2		// no more nibbles expected, clean up and return
	lsl r1, #4				// shift word over 4 bits to receive the next nibble
	mov r0, r3				// restore the original character for echo
	bl uart0_out			// echo the character 
	b ascii2hex_loop		// get another character
ascii2hex_2:
	mov r0, r3				// restore the original character for last echo
	bl uart0_out			// echo the last character 
	pop {r0, r2, r3, pc}	// return with word in r1
	
	
.align 4	
defined_data:

.equ ROM_FN_TBL,	0x00000014	// Pointer to a public function lookup table (rom_func_table) 
.equ ROM_TBL_PNT,	0x00000018	// Pointer to a helper function (ROM_TBL_PNT())	
.equ rosc_freq,	0x00fabfa0	// base for rosc frequency range, add 4 through 8
.equ clck_base,	0x40008000	// Clock register base address
.equ clck_aset,	0x4000a000	// Clock atomic set
.equ rst_base, 	0x4000c000	// reset controller base 2.14.3
.equ rst_set, 		0x4000e000 	// atomic register for setting reset controller 2.1.2
.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
.equ iob0_rw, 		0x40014000	// iobank_0 base address 2.19.6.1
.equ iob0a_rw,		0x40014080 	// iobank_0 base address starting at GPIO16 2.19.6.1
.equ ctrl_gp04,	0x40014024	// GPIO04_CTRL 2.19.6.1
.equ ctrl_gp21,	0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ ctrl_gp25,	0x400140cc	// GPIO25_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ xosc_rw, 		0x40024000 	// Base for xosc 2.16.7
.equ pll_sys_base,	0x40028000// PLL system registers base address
.equ pll_sys_aclr,	0x4002b000//  PLL system atomic clear base address
.equ uart0_rw,		0x40034000	// UART0 register base address 4.2.8
.equ rosc_base,	0x40060000	// Ring oscillator base 2.17.8
.equ rosc_aset,	0x40062000	// Ring oscillator atomic set register
.equ xosc_base,	0x40024000	// XOSC Base address
.equ xosc_aset,	0x40026000	// XOSC atomic set
.equ xosc_en,		0x00fab000	// enable for xosc
.equ rosc_pw, 		0x96960000	// ring oscillator password 2.17.8
.equ rosc_powr,	0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
.equ sio_base, 	0xd0000000	// SIO base 2.3.1.7
.equ big_num, 		0x00780000	// large number for the delay loop
.equ pio0_prog_base,	0x50200048// start of the pio0 program memory
.equ pio0_base, 	0x50200000	// start of the PIO0 registers
.equ pio0_base2,	0x50200080 	// start of second half of PIO0 registers
.equ pio0_aset, 	0x50202000	// start of atomic set for PIO0 registers
.equ pio0_aset2, 	0x50202080 	// start of second half of PIO0 atomic registers
.equ sm0_pinctl,	0x0c000080 	// setting gpio4 and 1 pins for set sm0pinctrl
.equ sm0_execctrl,	0x0001f000// no sticky, 0x1f top wrap, 0x0 bottom wrap, 
.equ sm0_clkdiv, 	0xffff0000	// really slow state machine 0 clock 
.equ jmp_to_0,		0x00000000	// jmp 0

.align 4
.section .data, "aw"

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




