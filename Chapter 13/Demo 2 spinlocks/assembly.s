/* bare metal assembly
Life with David - BMA Chapter 13_2 - 2nd Core Demo - 
Demonstrates spinlocks by outputting "SOS" on GPIO25

 Copyright (C) 2023  David Minderman

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.  

*************************************
This emulator runs on the Raspberry Pi Pico.   
*/
.cpu cortex-m0plus
.thumb



.section .reset, "ax"

.word __main_start__			// VMA for main section
.word __data_end__				// VMA for end of SRAM 
.word __main_load_start__		// LMA for main section
.word __emu_start__			// VMA for 6502 memory
.word __emu_end__				// VMA for 6502 memory end
.word __emu_load_start__ 		// LMA for 6502 program



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



// ***************Set up PLL**************************
	
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
	
// ************************peripheral reset ***********************	
		
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
	ldr r0, =clck_base   	// Base for clocks register
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
	ldr r0, =rst_base	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #1			// load 1 in bit 1 of register 2 
	lsl r2, r2, #22		// shift over 22 bits for UART0
	and r1, r1, r2		// isolate bit 22
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
	str r1, [r0, #0x028]   	// store in fractional baud rate register, UARTFBRD 4.2.8


// ************** uart word length and fifos **************
// *****************either*************************
/*	
// set word length (8 bits) and ENABLE FIFOs UARTLCR_H 4.2.8
set_word_len:
	mov r1, #112			// 0b01110000 = 112 (UARTLCR_H) (112: fifos enabled, 96: fifos disabled)
	str r1, [r0, #0x02c]  	// store in UARTLCR_H
*/
// *******************or**************************

// set word length (8 bits) and DISABLE FIFOs UARTLCR_H 4.2.8
// then set interrupt mask RXIM so a single key press will interrupt 
set_word_len:
	mov r1, #96				// 0b01100000 = 96 (UARTLCR_H) (112: fifos enabled, 96: fifos disabled)
	str r1, [r0, #0x02c]  	// store in UARTLCR_H
	mov r1, #16				// sets bit 4 for RXIM 
	str r1, [r0, #0x38]		// store in UARTIMSC
// ***********************************************
	
// Connect UART0 on iobank_0 pads 0 and 1 using "Function 2"   2.19.2
config_uart_gpio:
	ldr r0, =iob0_rw	  	//base address iobank_0 			2.19.6.1
	mov r1, #2			  	// function 2 UART0_TX & UART0_RX  2.19.2
	str r1, [r0, #4]  		//store function 2 in GPIO0_CTRL  2.19.6.1
	str r1, [r0, #0x0c]    //store function 2 in GPIO1_CTRL  2.19.6.1	

// ************** init NVIC for uart0 handler ***************
	ldr r0, =nvic_enable	// load in NVIC enable base address
	mov r1, #1				// set bit 0
	lsl r1, #20				// move set bit over to  bit 20
	str r1, [r0, #0]		// store in NVIC_ISER (2.4.8.)
	
// **************init PIO 0 *******************************

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

start_memcpy:
	bl do_memcpy44
	ldr r0, =__main_start__	// start of start1 VMA from linker
	ldr r1, =#1					// load "1" into reg 1 in order to...
	orr r0, r0, r1				// set bit 0 to tell "bx" to stay in THUMB mode
	bx r0						// now branch to "start1" and stay in THUMB mode
	b start_memcpy				// this is just a trap to make sure the BX above is working

do_memcpy44:           		// refer to 2.8.3.1.2. Fast Bulk Memory Fill / Copy Functions
    push {lr}
// **************copy the main program to RAM ***********************
    ldr r0, =ROM_FN_TABLE      //0x00000014
    ldrh r0, [r0]
    ldr r2, =ROM_TABLE_LOOKUP  //0x00000018
    ldrh r2, [r2]					

    // Query the bootrom function pointer
    ldr r1, =0x3443 					// 'C','4' for _memcpy44
    blx r2

    //uint8_t *_memcpy44(uint32_t *dest, uint32_t *src, uint32_t n)
    mov r3, r0							// load memcopy function pointer into r3
    ldr r0, =__main_start__        	// start of range to copy to
	ldr r2, =__data_end__				// end of range to copy to 
	sub r2, r2, r0						// number of bytes to copy (__data_end__ - __main_start__) 
    ldr r1, =__main_load_start__ 		// start of range to copy from
    blx r3								// call memcopy subroutine
 // ***************copy the 6502 memory to EMU RAM  *********************
    ldr r0, =ROM_FN_TABLE      //0x00000014
    ldrh r0, [r0]
    ldr r2, =ROM_TABLE_LOOKUP  //0x00000018
    ldrh r2, [r2]					

    // Query the bootrom function pointer
    ldr r1, =0x3443 					// 'C','4' for _memcpy44
    blx r2

    //uint8_t *_memcpy44(uint32_t *dest, uint32_t *src, uint32_t n)
    mov r3, r0							// load memcopy function pointer into r3
    ldr r0, =__emu_start__        		// start of range to copy to
	ldr r2, =__emu_end__				// end of range to copy to 
	sub r2, r2, r0						// number of bytes to copy (__emu_end__ - __emu_start__) 
    ldr r1, =__emu_load_start__ 		// start of range to copy from
    blx r3 
    pop {pc}
	

.align 4
.section .resetdata, "a"

reset_data:
.equ ROM_FN_TABLE,		0x00000014		// Pointer to a public function lookup table (rom_func_table) 
.equ ROM_TABLE_LOOKUP,	0x00000018		// Pointer to a helper function (rom_table_lookup())	
.equ rosc_freq,		0x00fabfa0	// base for rosc frequency range, add 4 through 8
.equ clck_base,		0x40008000	// Clock register base address
.equ clck_aset,		0x4000a000	// Clock atomic set
.equ rst_base, 		0x4000c000	// reset controller base 2.14.3
.equ rst_set, 		0x4000e000 	// atomic register for setting reset controller 2.1.2
.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
.equ iob0_rw, 		0x40014000	// iobank_0 base address 2.19.6.1
.equ iob0a_rw,		0x40014080 	// iobank_0 base address starting at GPIO16 2.19.6.1
.equ ctrl_gp04,		0x40014024	// GPIO04_CTRL 2.19.6.1
.equ ctrl_gp21,		0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ ctrl_gp25,		0x400140cc	// GPIO25_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ xosc_rw, 		0x40024000 	// Base for xosc 2.16.7
.equ pll_sys_base,	0x40028000	// PLL system registers base address
.equ pll_sys_aclr,	0x4002b000	//  PLL system atomic clear base address
.equ uart0_rw,		0x40034000	// UART0 register base address 4.2.8
.equ rosc_base,		0x40060000	// Ring oscillator base 2.17.8
.equ rosc_aset,		0x40062000	// Ring oscillator atomic set register
.equ xosc_base,		0x40024000	// XOSC Base address
.equ xosc_aset,		0x40026000	// XOSC atomic set
.equ xosc_en,		0x00fab000	// enable for xosc
.equ rosc_pw, 		0x96960000	// ring oscillator password 2.17.8
.equ rosc_powr,		0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
.equ sio_base, 		0xd0000000	// SIO base 2.3.1.7
.equ big_num, 		0x00780000	// large number for the delay loop
.equ nvic_enable, 	0xe000e100	// set interrupt enable


.cpu cortex-m0plus
.thumb
.section .main, "ax"

.cpu cortex-m0plus
.thumb
.section .core_init, "ax"

.equ core1_vt,			0x10000100 // Core 1 vector table, right now set to core 0 **Revisit as needed**
.equ core1_stack,		0x20041000 // Core 1 stack pointer ****REVISIT as needed****	

// set up GPIO 4 & 5	
	ldr r0, =ctrl_gp04
	mov r1, #5				// load function 5 for GPIO
	str r1, [r0]			// Store function_5 in GPIO04 control register 2.19.6.1
	str r1, [r0, #8]		// Store function_5 in GPIO05 control register 2.19.6.1
	bl init_core			// initializes and starts core 1

.align	
entry_c0:					// blinks 3 quick blinks and a long delay for core 0
	ldr r0, =spin_base		//load spinlock base
entry_c0_loop:	
	ldr r1, [r0, #0]		// query spinlock 0
	cmp r1, #0				// is spinlock 0 already claimed?
	beq entry_c0_loop		// yes it is, just keep spinning
	mov r0, #03				// spinlock 0 claimed so load in 3
	bl led_count			// blink led_count
	bl delay				// longer delay to separate blink packets			
	ldr r0, =spin_base		//	load spinlock base
	str r1, [r0, #0]		// writing ANY value releases the spinlock
	nop						// delay to allow core 1 to claim spinlock
	b entry_c0				// do it again
	
init_core:					// starts up second core (section 2.8.2)
							// data to send: {0, 0, 1, vector table address, stack pointer address, entry address}
	push {lr}
init_core1:	
	bl fifo_drain			// drain the fifo (Section 2.8.2)
	mov r0, #0				// load the first word of "0, 0, 1" to start core 1 (the second core)
	bl fifo_send			// send 0 to the core 1	
	bl fifo_recv			// read the echo back
	cmp r0, #0				// compare the echo with 0
	bne init_core1			// readback wasn't correct, so start over

	bl fifo_drain			// drain the fifo (Section 2.8.2)
	mov r0, #0				// load the second word of "0, 0, 1" to start core 1 (the second core)
	bl fifo_send			// send 0 to the core 1
	bl fifo_recv			// read the echo back
	cmp r0, #0				// compare the echo with 0
	bne init_core1			// readback wasn't correct, so start over
	
	mov r0, #1				// load the third word of "0, 0, 1" to start core 1 (the second core)
	bl fifo_send			// send 1 to the core 1
	bl fifo_recv			// read the echo back
	cmp r0, #1				// compare the echo with 1
	bne init_core1			// readback wasn't correct, so start over
	
	ldr r4, =core1_vt		// load a vector table address (junk this time)
	mov r0, r4				// move value to r0 for sending to fifo 
	bl fifo_send			// send 0 to the core 1
	bl fifo_recv			// read the echo back
	cmp r0, r4				// compare the echo 
	bne init_core1			// readback wasn't correct, so start over
	
	ldr r4, =core1_stack	// load a stack address for core 1
	mov r0, r4				// move value to r0 for sending to fifo
	bl fifo_send			// send stack address to the core 1
	bl fifo_recv			// read the echo back
	cmp r0, r4				// compare the echo 
	bne init_core1			// readback wasn't correct, so start over
	
	adr r4, entry_c1		// load the entry address for core 1
	add r4, #1				// convert entry address to thumb mode
	mov r0, r4				// move value to r0 for sending to fifo
	bl fifo_send			// send entry address to the core 1
	bl fifo_recv			// read the echo back
	cmp r0, r4				// compare the echo 
	bne init_core1			// readback wasn't correct, so start over
	bl delay
	pop {pc}
.align
entry_c1:					// claim spinlock 0, blinks 3 long blinks, long delay, release spinlock 0, 
							// claim spinlock 0, very long delay, then release spinlock 0
	ldr r0, =spin_base		// load spinlock base
	ldr r1, [r0, #0]		// query spinlock 0
	cmp r1, #0				// is spinlock 0 already claimed?
	beq entry_c1			// yes it is, just keep spinning
	mov r0, #3				// spinlock 0 claimed so load in 3
	bl led_long_count		// blink led_count
	bl delay				// longer delay to separate blink packets
	ldr r0, =spin_base		// load spinlock base
	str r1, [r0, #0]		// writing ANY value releases the spinlock
	nop
	nop
	ldr r0, =spin_base		// load spinlock base
entry_c1_loop:			// this is for making a very long delay
	ldr r1, [r0, #0]		// query spinlock 0
	cmp r1, #0				// is spinlock 0 already claimed?
	beq entry_c1_loop		// yes it is, just keep spinning
	bl delay				// spinlock 0 claimed- so longer delay to separate blink packets			
	bl delay
	bl delay
	bl delay
	bl delay
	ldr r0, =spin_base		// load spinlock base
	str r1, [r0, #0]		// writing ANY value releases the spinlock
	nop
	b entry_c1			// do it again and again
	
fifo_drain:
	push {lr}
fifo_drain_loop:	
	ldr r0, =sio_base
	ldr r1, [r0, #0x58]		// load in data in fifo
	ldr r1, [r0, #0x50]		// load in status bit
	mov r2, #1				// mask to see if fifo is empty
	and r1, r2				// use mask to siolat bit 0
	bne fifo_drain_loop	// there is still data in fifo so branch back to beginning
	sev						// send an event
	pop {pc}

fifo_send:
	push {lr}
fifo_send_loop:	
	ldr r1, =sio_base
	ldr r2, [r1, #0x50]		// load reg 2 with fifo status
	mov r3, #2				// load mask for fifo not full
	and r2, r3				// use mask to isolate bit 1
	beq fifo_send_loop	// if fifo is full then spin on fifo_send
	str r0, [r1, #0x54]		// send data to transmit fifo register
	sev
	pop {pc}

fifo_recv:
	push {r4,lr}
fifo_recv_rtrn:	
	ldr r1, =sio_base
	ldr r2, [r1, #0x50]		// load reg 2 with fifo status
	mov r3, #1				// load mask for fifo not empty
	and r2, r3				// use mask to isolate bit 0
	beq fifo_wait			// if fifo is empty then spin on fifo_wait to wait for event
	ldr r0, [r1, #0x58]		// get data from fifo register
	pop {r4,pc}
	
fifo_wait:
	wfe						// wait for event
	b fifo_recv_rtrn		// received event so go back to fifo_recv

led_count:  				// blinks GPIO25 the number of times that is in r0 
	push {lr}
	mov r3, r0
led_count0:
	cmp r3, #0
	beq led_count1	
	bl led_on
	bl delay
	bl led_off
	bl delay
	sub r3, #1
	b led_count0
led_count1:	
	pop {pc}

led_long_count:
	push {lr}
	mov r3, r0
led_long_count0:
	cmp r3, #0
	beq led_long_count1	
	bl led_on
	bl delay
	bl delay
	bl delay
	bl led_off
	bl delay
	bl delay
	bl delay
	sub r3, #1
	b led_long_count0
led_long_count1:	
	pop {pc}
.thumb
.section .comms, "ax"	


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
	b reg_prt_2				// branch to ascii out
reg_prt_1:				
	add r0, #87				// convert to a letter
reg_prt_2:
	bl uart0_out			// output the character
	cmp r5, #0				// are we done?
	bne reg_prt_0			// if not, do it again
	pop {r0,r1,r4,r5,pc}	// if done, then return

prt_4ascii:				// print 4 ascii characters in one 32 bit word held in r1
							// first letter in lowest byte (i.e. message backwards in word)
	push {r0, r1, r2, lr}
	mov r0, #0xff
	and r0, r0, r1			// isolate 8 lsb and put in r0
	bl uart0_out
	lsr r1, #8				// shift to next character
	mov r0, #0xff
	and r0, r0, r1
	bl uart0_out 
	lsr r1, #8				// shift to next character
	mov r0, #0xff
	and r0, r0, r1
	bl uart0_out	
	lsr r1, #8				// shift to next character
	mov r0, #0xff
	and r0, r0, r1
	bl uart0_out	
	pop {r0, r1, r2, pc}
	
prt_byte:					// prints one byte of hex data in r7 
	push {r0-r7, lr}
	mov r4, r7				// stash r7 into r4
	mov r5, #8				// number of bits per register
prt_byte_0:
	sub r5, #4				// calculate the number of bits to shift
	mov r0, r4 				// refresh r0 with original word
	lsr r0, r5				// shift to get desired nibble into 4 lsbits
	mov r1, #15				// bit mask for 4 LSBits
	and r0, r1				// isolate 4 LSBits
	cmp r0, #9				// is it a number?
	bhi prt_byte_1			// if not, make it a letter (a-f)
	add r0, #48				// convert number to ascii
	b prt_byte_2				// branch to ascii out
prt_byte_1:				
	add r0, #87				// convert to a letter
prt_byte_2:
	bl uart0_out			// output the character
	cmp r5, #0				// are we done?
	bne prt_byte_0			// if not, do it again
	pop {r0-r7,pc}			// if done, then return
	
	
	
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

uart0_null:				// This forces a null character to clear tx busy
	push {r0, r1, lr}
	ldr r1, =uart0_rw 		// base address for uart0 registers
	mov r0, #0				// load in null
	str r0, [r1, #0]		// store data in uart data register, UARTDR
	pop {r0, r1, pc}
	

uart0_out:					// data out in r0
	push {r0,r1,r2,r3,lr}
	
uart0_out_loop:		
	ldr r1, =uart0_rw 		// base address for uart0 registers
	ldr r2, [r1, #0x18]		// read UART0 flag register UARTFR 4.2.8
//	mov r3, #32				// mask for bit 5, TX FIFO full TXFF
	mov r3, #8				// mask for bit 3, UART BUSY 
	and r2, r3				// isolate bit 5
	bne uart0_out_loop		// if TX FIFO is full, go back and check again
//	bl delay
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
	bne uart0_in_loop	 	// if RX FIFO is empty, go back and check again
	ldr r0, [r1, #0] 		// load data from uart data register into r0, UARTDR
	pop {r1,r2,r3,pc}		//return
	
echo_in:
	push {lr}
	bl uart0_in				// get a character
	bl uart0_out			// and echo it out
	pop {pc}				// and return
	
print_registers:
	push {r0,r1,lr}	
	bl prt_cr_lf		// ***************
	ldr r1, =PC_
	bl prt_4ascii
	ldr r0, [sp, #12]	// get pc at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************	
	ldr r1, =R0_
	bl prt_4ascii
	ldr r0, [sp, #0] 			// get r0 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R1_
	bl prt_4ascii
	ldr r0, [sp, #4] 			// get r1 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R2_
	bl prt_4ascii
	mov r0, r2 			// get r2 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R3_
	bl prt_4ascii
	mov r0, r3 			// get r3 at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	ldr r1, =R4_
	bl prt_4ascii
	mov r0, r4			// get r4 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************	
	ldr r1, =R5_
	bl prt_4ascii
	mov r0, r5			// get r5 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R6_
	bl prt_4ascii
	mov r0, r6			// get r6 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R7_
	bl prt_4ascii
	mov r0, r7			// get r7 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R8_
	bl prt_4ascii
	mov r0, r8			// get r8 at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	ldr r1, =R9_
	bl prt_4ascii
	mov r0, r9			// get r9 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R10_
	bl prt_4ascii
	mov r0, r10			// get r10 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R11_
	bl prt_4ascii
	mov r0, r11			// get r11 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R12_
	bl prt_4ascii
	mov r0, r12			// get r12 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =SP_
	bl prt_4ascii
	mov r0, sp			// get SP at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	pop {r0, r1 ,pc}
stop:
	b stop				// this single steps processor
		
// ****************ascii to hex ***********************

ascii2hex:					// converts ascii input into a binary word
	push {r0, r2, r3, lr}
	mov r2, #8				// number of hex characters (nibbles) expected
	mov r1, #0				// clear r1 to accept built binary character
ascii2hex_loop:	
	bl uart0_in				// get ascii character in r0
	mov r3, r0 				// memorialize the original character
	cmp r0, #0x30			// could character be a letter or number?
	blo ascii2hex_loop		// no, go back and get another ascii character
	cmp r0, #0x39			// could character be a number?
	bhi ascii2hex_0		// no. see if it a letter a-f
	sub r0, r0, #0x30		// it's a number so convert it to a nibble (0x0 to 0x9)
	b ascii2hex_1			// branch to building the word
ascii2hex_0:
	cmp r0, #0x61			// could character be a letter?
	blo ascii2hex_loop		// no, go back and get another character
	cmp r0, #0x66			// character is a letter, could it be a-f?
	bhi ascii2hex_loop		// no, go back and get another character
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

.equ ROM_FN_TABLE,		0x00000014		// Pointer to a public function lookup table (rom_func_table) 
.equ ROM_TABLE_LOOKUP,	0x00000018		// Pointer to a helper function (rom_table_lookup())	
.equ rosc_freq,		0x00fabfa0	// base for rosc frequency range, add 4 through 8
.equ clck_base,		0x40008000	// Clock register base address
.equ clck_aset,		0x4000a000	// Clock atomic set
.equ rst_base, 		0x4000c000	// reset controller base 2.14.3
.equ rst_set, 		0x4000e000 	// atomic register for setting reset controller 2.1.2
.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
.equ iob0_rw, 		0x40014000	// iobank_0 base address 2.19.6.1
.equ iob0a_rw,		0x40014080 	// iobank_0 base address starting at GPIO16 2.19.6.1
.equ ctrl_gp04,		0x40014024	// GPIO04_CTRL 2.19.6.1
.equ ctrl_gp21,		0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ ctrl_gp25,		0x400140cc	// GPIO25_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL
.equ xosc_rw, 		0x40024000 	// Base for xosc 2.16.7
.equ pll_sys_base,	0x40028000	// PLL system registers base address
.equ pll_sys_aclr,	0x4002b000	//  PLL system atomic clear base address
.equ uart0_rw,		0x40034000	// UART0 register base address 4.2.8
.equ rosc_base,		0x40060000	// Ring oscillator base 2.17.8
.equ rosc_aset,		0x40062000	// Ring oscillator atomic set register
.equ xosc_base,		0x40024000	// XOSC Base address
.equ xosc_aset,		0x40026000	// XOSC atomic set
.equ xosc_en,		0x00fab000	// enable for xosc
.equ rosc_pw, 		0x96960000	// ring oscillator password 2.17.8
.equ rosc_powr,		0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
.equ sio_base, 		0xd0000000	// SIO base 2.3.1.7
.equ spin_base,		0xd0000100// spinlock base address 2.3.1.7
.equ big_num, 		0x00780000	// large number for the delay loop
.equ pio0_prog_base,	0x50200048		// start of the pio0 program memory
.equ pio0_base, 	0x50200000	// start of the PIO0 registers
.equ pio0_base2,	0x50200080 // start of second half of PIO0 registers
.equ pio0_aset, 	0x50202000	// start of atomic set for PIO0 registers
.equ pio0_aset2, 	0x50202080 // start of second half of PIO0 atomic registers
.equ sm0_pinctl,	0x0c000080 // setting gpio4 and 1 pins for set sm0pinctrl
.equ sm0_execctrl,	0x0001f000 // no sticky, 0x1f top wrap, 0x0 bottom wrap, 
.equ sm0_clkdiv, 	0xffff0000	// really slow state machine 0 clock 
.equ lsbyte_mask, 	0x000000ff 	// least significant byte mask
.equ uart_6502_base,	0x0000e800	// 6502 true char in address (0xe801 6502 out)
.equ uart_sr_6502, 0x0000e805	// 6502 true uart status address, bit 5 (0=write full), bit 0 (1=read full)
.equ int_vector,	0xfffe		// location of interrupt vector
.equ reset_vector,	0xfffc		// location of reset vector
.equ nmi_vector, 	0xfffa		// location of nmi vector
.equ mem_str_6502, 0x20020000	// start of 6502 memory

			
.equ jmp_to_0,		0x00000000	// jmp 0
.equ R0_,			0x3a303052	// "R00:"
.equ R1_,			0x3a313052	// "R01:"
.equ R2_,			0x3a323052	// "R02:"
.equ R3_,			0x3a333052	// "R03:"
.equ R4_,			0x3a343052	// "R04:"
.equ R5_,			0x3a353052	// "R05:"
.equ R6_,			0x3a363052	// "R06:"
.equ R7_,			0x3a373052	// "R07:"
.equ R8_,			0x3a383052	// "R08:"
.equ R9_,			0x3a393052	// "R09:"
.equ R10_,			0x3a303152	// "R10:"
.equ R11_,			0x3a313152	// "R11:"
.equ R12_,			0x3a323152	// "R12:"
.equ SP_,			0x3a205053	// "SP :"
.equ LR_,			0x3a524c20	// " LR:"
.equ PC_,			0x3a204350	// "PC :"
.equ CURR,			0x52525543	// "CURR"
.equ PREV,			0x56455250	// "PREV"





.thumb
.section .int_handler, "ax"

// **************interrupt handlers **********************************

.type _uart0_isr, %function
.thumb_func
.global _uart0_isr
_uart0_isr:


// clear the Uart receive interrupt
// only use one of the two programs listed 
/*  ******************This will grab a character from the keyboard for 6502
	push {lr}
	ldr r1, =uart0_rw 	// base address for uart0 registers
	ldr r0, [r1, #0] 	// load data from uart data register into r0, UARTDR
	mov r2, #0xff
	and r0, r0, r2		// isolate 8 lsbs
	ldr r1, =__6502_uart_base__	// the pointer for "__6502_uart_base__"
	ldr r1, [r1, #0]		// get the value of "__6502_uart_base__"
	strb r0, [r1, #0]		// store character for 6502
	ldrb r2, [r1, #0x5]	// 6502 uart SR in r2	
	mov r0, #1			// bit mask for emulated uart read
	orr r2, r2, r0		// set bit 0, indicates read char available
	strb r2, [r1, #0x5]	// store "UART" status back for 6502
	pop {pc}			// return
*/
// ************************* OR ******************************
// ***********this prints registers after a semicolon is pressed	
	push {lr}
	mov r3, lr			// memorialize current lr in r3
	ldr r1, =uart0_rw 	// base address for uart0 registers
	ldr r0, [r1, #0] 	// load data from uart data register into r0, UARTDR
	mov r2, #0xff
	and r0, r0, r2		// isolate 8 lsbs
	cmp r0, #0x3b		// ascii ";"
	beq uart0_isr_cont // if it's an ";" then print registers
	cmp r0, #0x6d		// if it's an "m" then dump memory
	beq dump_mem
	pop {pc}			// it's not a ";" or "m" so return
	
dump_mem:						// prints mem block 
	ldr r1, =mem_str_6502		// start of 6502 memory
	mov r3, #0x08				// number of lines to print
new_line:	
	bl prt_cr_lf				// start a new line
	mov r2, #0x10				// number of bytes per line
	mov r0, r1					// prep to print address
	bl reg_prt					// print the memory location
	bl prt_spc					// print a space
get_byte:
	ldrb r7, [r1, #0]			// get byte to print
	
	bl prt_byte				// print the byte
	bl prt_spc					// space between bytes
	add r1, r1, #1				// increment memory pointer
	sub r2, r2, #1				// dec number of bytes left to print on line	
	beq next_line				// if done with line, then start a new line
next_char:
	b get_byte					// get and print the next byte
next_line:
	mov r2, #0x10				// number of bytes to print on new line
	sub r3, r3, #1				// decrement number of lines to print
	bne new_line				// if there are more lines to print, then do it
	pop {pc}					// if not, then return

	
uart0_isr_cont:
	bl prt_cr_lf		// ***************
	ldr r1, =PC_
	bl prt_4ascii
	ldr r0, [sp, #0x1c]	// get pc at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************	
	ldr r1, =R0_
	bl prt_4ascii
	ldr r0, [sp, #04]	// get r0 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R1_
	bl prt_4ascii
	ldr r0, [sp, #0x08]	// get r1 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R2_
	bl prt_4ascii
	ldr r0, [sp, #0x0c]	// get r2 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R3_
	bl prt_4ascii
	ldr r0, [sp, #0x10]	// get r3 at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	ldr r1, =R4_
	bl prt_4ascii
	mov r0, r4			// get r4 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************	
	ldr r1, =R5_
	bl prt_4ascii
	mov r0, r5			// get r5 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R6_
	bl prt_4ascii
	mov r0, r6			// get r6 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R7_
	bl prt_4ascii
	mov r0, r7			// get r7 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R8_
	bl prt_4ascii
	mov r0, r8			// get r8 at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	ldr r1, =R9_
	bl prt_4ascii
	mov r0, r9			// get r9 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R10_
	bl prt_4ascii
	mov r0, r10			// get r10 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R11_
	bl prt_4ascii
	mov r0, r11			// get r11 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =R12_
	bl prt_4ascii
	mov r0, r12			// get r12 at time of interrupt
	bl reg_prt
	bl prt_spc		// ***************
	ldr r1, =SP_
	bl prt_4ascii
	mov r0, sp			// get SP at time of interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	ldr r1, =CURR
	bl prt_4ascii
	ldr r1, =LR_
	bl prt_4ascii
	mov r0, r3			// get lr just after the interrupt
	bl reg_prt	
	bl prt_cr_lf		// ***************
	ldr r1, =PREV
	bl prt_4ascii
	ldr r1, =LR_
	bl prt_4ascii
	ldr r0, [sp, #0x18]	// get lr just before interrupt
	bl reg_prt
	bl prt_cr_lf		// ***************
	pop {pc}			// return
		
/*
.align 4
.section .emudata, "aw"

_6502_prog:
.byte	0x20		//jsr		char_in	 		;get a character
.byte	0x09 
.byte	0x00     
.byte 	0x20		//jsr		char_out			; write a character
.byte	0x1f 
.byte	0x00     			
.byte 	0x4c		//jmp		emu_echo			; and do again		
.byte	0x00 
.byte	0x00     			
// character in subroutine, character in acc, x is cleared
.byte 	0xA9		//char_in:	lda 	#$01	; Load staus register
.byte	0x01        
.byte 	0x2C		//bit 	$e805					; test bit 0
.byte	0x05 
.byte	0xE8     			
.byte	0xF0		//beq 	char_in				; no character so check again
.byte	0xF9        			
.byte	0xAE		//ldx		$e800				; load character into x
.byte	0x00 
.byte	0xE8     			
.byte	0xAD		//lda 	$e805					; load status register again
.byte	0x05 
.byte	0xE8     			
.byte	0x29		//and 	#$fe					; clear bit 0
.byte	0xFE        			
.byte	0x8D		//sta 	$e805					; store status register again
.byte	0x05 
.byte	0xE8     			
.byte	0x8A		//txa							; transfer character to acc register
.byte	0xA2		//ldx 	#$00					; clear x reg.
.byte	0x00        			
.byte	0x60		//rts							; return
// character out subroutine, character in acc, acc and x are cleared
.byte	0x48		//char_out:	pha				; push acc and cr to stack
.byte	0x08		//php
.byte	0xA9 			
.byte	0x20		//ch_loop:	lda		#$20	; load bit 5 mask
.byte	0x2C		//bit 	$e805					; test bit 5, if bit 5 set then ready to send
.byte	0x05 
.byte	0xE8     			
.byte	0xD0		//bne	ch_loop				; last character not read; wait
.byte	0xF9        			
.byte	0x28		//plp							; pop cr and acc
.byte	0x68		//pla
.byte 	0x8D		//sta	$e801					; store character in character out (e801)
.byte	0x01 
.byte	0xE8     			
.byte	0xAD		//lda	$e805					; load UART status register
.byte	0x05 
.byte	0xE8     			
.byte	0x09		//ora 	#$20					; clear bit 5
.byte	0x20        			
.byte 	0x8D		//sta	$e805					; store status register
.byte	0x05 
.byte	0xE8     			
.byte	0xA2		//ldx 	#$00					; clear x reg
.byte	0x00        			
.byte 	0xA9		//lda	#$00 					; clear acc
.byte	0x00        					
.byte	0x60		//rts							; return					
*/	


.end


