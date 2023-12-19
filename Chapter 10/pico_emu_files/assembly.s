//bare metal assembly
//Life with David - Bare Metal Adventures, Chapter 10 - Pico based 6502 Emulator 
/*
 RP2040 (Pico) based 6502 emulator

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

// 6502 Emulator Instruction Vector Table; Life with David-BMA09
// 

.cpu cortex-m0plus
.thumb
	

.section .emu_vector, "ax"
//.align 4
_vector_inst:
.word	_brk_imp	// 0x00
.word	_ora_x_ind	// 0x01
.word	_error_1	// 0x02
.word	_error_1	// 0x03
.word	_error_1	// 0x04
.word	_ora_zpg	// 0x05
.word	_asl_zpg	// 0x06
.word	_error_1	// 0x07
.word	_php_imp	// 0x08
.word	_ora_imm	// 0x09
.word	_asl_a		// 0x0a
.word	_error_1	// 0x0b
.word	_error_1	// 0x0c
.word	_ora_abs	// 0x0d
.word	_asl_abs	// 0x0e
.word	_error_1	// 0x0f
.word	_bpl_rel	// 0x10
.word	_ora_ind_y	// 0x11
.word	_error_1	// 0x12
.word	_error_1	// 0x13
.word	_error_1	// 0x14
.word	_ora_zpg_x	// 0x15
.word	_asl_zpg_x	// 0x16
.word	_error_1	// 0x17
.word	_clc_imp	// 0x18
.word	_ora_abs_y	// 0x19
.word	_error_1	// 0x1a
.word	_error_1	// 0x1b
.word	_error_1	// 0x1c
.word	_ora_abs_x	// 0x1d
.word	_asl_abs_x	// 0x1e
.word	_error_1	// 0x1f
.word	_jsr_abs	// 0x20
.word	_and_x_ind	// 0x21
.word	_error_1	// 0x22
.word	_error_1	// 0x23
.word	_bit_zpg	// 0x24
.word	_and_zpg	// 0x25
.word	_rol_zpg	// 0x26
.word	_error_1	// 0x27
.word	_plp_imp	// 0x28
.word	_and_imm	// 0x29
.word	_rol_a		// 0x2a
.word	_error_1	// 0x2b
.word	_bit_abs	// 0x2c
.word	_and_abs	// 0x2d
.word	_rol_abs	// 0x2e
.word	_error_1	// 0x2f
.word	_bmi_rel	// 0x30
.word	_and_ind_y	// 0x31
.word	_error_1	// 0x32
.word	_error_1	// 0x33
.word	_error_1	// 0x34
.word	_and_zpg_x	// 0x35
.word	_rol_zpg_x	// 0x36
.word	_error_1	// 0x37
.word	_sec_imp	// 0x38
.word	_and_abs_y	// 0x39
.word	_error_1	// 0x3a
.word	_error_1	// 0x3b
.word	_error_1	// 0x3c
.word	_and_abs_x	// 0x3d
.word	_rol_abs_x	// 0x3e
.word	_error_1	// 0x3f
.word	_rti_imp	// 0x40
.word	_eor_x_ind	// 0x41
.word	_error_1	// 0x42
.word	_error_1	// 0x43
.word	_error_1	// 0x44
.word	_eor_zpg	// 0x45
.word	_lsr_zpg	// 0x46
.word	_error_1	// 0x47
.word	_pha_imp	// 0x48
.word	_eor_imm	// 0x49
.word	_lsr_a		// 0x4a
.word	_error_1	// 0x4b
.word	_jmp_abs	// 0x4c
.word	_eor_abs	// 0x4d
.word	_lsr_abs	// 0x4e
.word	_error_1	// 0x4f
.word	_bvc_rel	// 0x50
.word	_eor_ind_y	// 0x51
.word	_error_1	// 0x52
.word	_error_1	// 0x53
.word	_error_1	// 0x54
.word	_eor_zpg_x	// 0x55
.word	_lsr_zpg_x	// 0x56
.word	_error_1	// 0x57
.word	_cli_imp	// 0x58
.word	_eor_abs_y	// 0x59
.word	_error_1	// 0x5a
.word	_error_1	// 0x5b
.word	_error_1	// 0x5c
.word	_eor_abs_x	// 0x5d
.word	_lsr_abs_x	// 0x5e
.word	_error_1	// 0x5f
.word	_rts_imp	// 0x60
.word	_adc_x_ind	// 0x61
.word	_error_1	// 0x62
.word	_error_1	// 0x63
.word	_error_1	// 0x64
.word	_adc_zpg	// 0x65
.word	_ror_zpg	// 0x66
.word	_error_1	// 0x67
.word	_pla_imp	// 0x68
.word	_adc_imm	// 0x69
.word	_ror_a		// 0x6a
.word	_error_1	// 0x6b
.word	_jmp_ind	// 0x6c
.word	_adc_abs	// 0x6d
.word	_ror_abs	// 0x6e
.word	_error_1	// 0x6f
.word	_bvs_rel	// 0x70
.word	_adc_ind_y	// 0x71
.word	_error_1	// 0x72
.word	_error_1	// 0x73
.word	_error_1	// 0x74
.word	_adc_zpg_x	// 0x75
.word	_ror_zpg_x	// 0x76
.word	_error_1	// 0x77
.word	_sei_imp	// 0x78
.word	_adc_abs_y	// 0x79
.word	_error_1	// 0x7a
.word	_error_1	// 0x7b
.word	_error_1	// 0x7c
.word	_adc_abs_x	// 0x7d
.word	_ror_abs_x	// 0x7e
.word	_error_1	// 0x7f
.word	_error_1	// 0x80
.word	_sta_x_ind	// 0x81
.word	_error_1	// 0x82
.word	_error_1	// 0x83
.word	_sty_zpg	// 0x84
.word	_sta_zpg	// 0x85
.word	_stx_zpg	// 0x86
.word	_error_1	// 0x87
.word	_dey_imp	// 0x88
.word	_error_1	// 0x89
.word	_txa_imp	// 0x8a
.word	_error_1	// 0x8b
.word	_sty_abs	// 0x8c
.word	_sta_abs	// 0x8d
.word	_stx_abs	// 0x8e
.word	_error_1	// 0x8f
.word	_bcc_rel	// 0x90
.word	_sta_ind_y	// 0x91
.word	_error_1	// 0x92
.word	_error_1	// 0x93
.word	_sty_zpg_x	// 0x94
.word	_sta_zpg_x	// 0x95
.word	_stx_zpg_y	// 0x96
.word	_error_1	// 0x97
.word	_tya_imp	// 0x98
.word	_sta_abs_y	// 0x99
.word	_txs_imp	// 0x9a
.word	_error_1	// 0x9b
.word	_error_1	// 0x9c
.word	_sta_abs_x	// 0x9d
.word	_error_1	// 0x9e
.word	_error_1	// 0x9f
.word	_ldy_imm	// 0xa0
.word	_lda_x_ind	// 0xa1
.word	_ldx_imm	// 0xa2
.word	_error_1	// 0xa3
.word	_ldy_zpg	// 0xa4
.word	_lda_zpg	// 0xa5
.word	_ldx_zpg	// 0xa6
.word	_error_1	// 0xa7
.word	_tay_imp	// 0xa8
.word	_lda_imm	// 0xa9
.word	_tax_imp	// 0xaa
.word	_error_1	// 0xab
.word	_ldy_abs	// 0xac
.word	_lda_abs	// 0xad
.word	_ldx_abs	// 0xae
.word	_error_1	// 0xaf
.word	_bcs_rel	// 0xb0
.word	_lda_ind_y	// 0xb1
.word	_error_1	// 0xb2
.word	_error_1	// 0xb3
.word	_ldy_zpg_x	// 0xb4
.word	_lda_zpg_x	// 0xb5
.word	_ldx_zpg_y	// 0xb6
.word	_error_1	// 0xb7
.word	_clv_imp	// 0xb8
.word	_lda_abs_y	// 0xb9
.word	_tsx_imp	// 0xba
.word	_error_1	// 0xbb
.word	_ldy_abs_x	// 0xbc
.word	_lda_abs_x	// 0xbd
.word	_ldx_abs_y	// 0xbe
.word	_error_1	// 0xbf
.word	_cpy_imm	// 0xc0
.word	_cpm_x_ind	// 0xc1
.word	_error_1	// 0xc2
.word	_error_1	// 0xc3
.word	_cpy_zpg	// 0xc4
.word	_cpm_zpg	// 0xc5
.word	_dec_zpg	// 0xc6
.word	_error_1	// 0xc7
.word	_iny_imp	// 0xc8
.word	_cmp_imm	// 0xc9
.word	_dex_imp	// 0xca
.word	_error_1	// 0xcb
.word	_cpy_abs	// 0xcc
.word	_cmp_abs	// 0xcd
.word	_dec_abs	// 0xce
.word	_error_1	// 0xcf
.word	_bne_rel	// 0xd0
.word	_cmp_ind_y	// 0xd1
.word	_error_1	// 0xd2
.word	_error_1	// 0xd3
.word	_error_1	// 0xd4
.word	_cmp_zpg_x	// 0xd5
.word	_dec_zpg_x	// 0xd6
.word	_error_1	// 0xd7
.word	_cld_imp	// 0xd8
.word	_cmp_abs_y	// 0xd9
.word	_error_1	// 0da
.word	_error_1	// 0db
.word	_error_1	// 0dc
.word	_cmp_abs_x	// 0xdd
.word	_dec_abs_x	// 0xde
.word	_error_1	// 0xdf
.word	_cpx_imm	// 0xe0
.word	_sbc_x_ind	// 0xe1
.word	_error_1	// 0xe2
.word	_error_1	// 0xe3
.word	_cpx_zpg	// 0xe4
.word	_sbc_zpg	// 0xe5
.word	_inc_zpg	// 0xe6
.word	_error_1	// 0xe7
.word	_inx_imp	// 0xe8
.word	_sbc_imm	// 0xe9
.word	_nop_imp	// 0xea
.word	_error_1	// 0xeb
.word	_cpx_abs	// 0xec
.word	_sbc_abs	// 0xed
.word	_inc_abs	// 0xee
.word	_error_1	// 0xef
.word	_beq_rel	// 0xf0
.word	_sbc_ind_y	// 0xf1
.word	_error_1	// 0xf2
.word	_error_1	// 0xf3
.word	_error_1	// 0xf4
.word	_sbc_zpg_x	// 0xf5
.word	_inc_zpg_x	// 0xf6
.word	_error_1	// 0xf7
.word	_sed_imp	// 0xf8
.word	_sbc_abs_y	// 0xf9
.word	_error_1	// 0xfa
.word	_error_1	// 0fb
.word	_error_1	// 0xfc
.word	_sbc_abs_x	// 0xfd
.word	_inc_abs_x	// 0xfe
.word	_error_1	// 0xff





// ************************emulator instruction routines *****************



.thumb_func
.type	_brk_imp,		%function	// 0x00
.type	_ora_x_ind,	%function	// 0x01
.type	_ora_zpg,		%function	// 0x05
.type	_asl_zpg,		%function	// 0x06
.type	_php_imp,		%function	// 0x08
.type	_ora_imm,		%function	// 0x09
.type	_asl_a,		%function	// 0x0a
.type	_ora_abs,		%function	// 0x0d
.type	_asl_abs,		%function	// 0x0e
.type	_bpl_rel,		%function	// 0x10
.type	_ora_ind_y,	%function	// 0x11
.type	_ora_zpg_x,	%function	// 0x15
.type	_asl_zpg_x,	%function	// 0x16
.type	_clc_imp,		%function	// 0x18
.type	_ora_abs_y,	%function	// 0x19
.type	_ora_abs_x,	%function	// 0x1d
.type	_asl_abs_x,	%function	// 0x1e
.type	_jsr_abs,		%function	// 0x20
.type	_and_x_ind,	%function	// 0x21
.type	_bit_zpg,		%function	// 0x24
.type	_and_zpg,		%function	// 0x25
.type	_rol_zpg,		%function	// 0x26
.type	_plp_imp,		%function	// 0x28
.type	_and_imm,		%function	// 0x29
.type	_rol_a,		%function	// 0x2a
.type	_and_abs,		%function	// 0x2d
.type	_bit_abs,		%function	// 0x2c
.type	_rol_abs,		%function	// 0x2e
.type	_bmi_rel,		%function	// 0x30
.type	_and_ind_y,	%function	// 0x31
.type	_and_zpg_x,	%function	// 0x35
.type	_rol_zpg_x,	%function	// 0x36
.type	_sec_imp,		%function	// 0x38
.type	_and_abs_y,	%function	// 0x39
.type	_and_abs_x,	%function	// 0x3d
.type	_rol_abs_x,	%function	// 0x3e
.type	_eor_x_ind,	%function	// 0x41
.type	_rti_imp,		%function	// 0x40
.type	_eor_zpg,		%function	// 0x45
.type	_lsr_zpg,		%function	// 0x46
.type	_pha_imp,		%function	// 0x48
.type	_eor_imm,		%function	// 0x49
.type	_lsr_a,		%function	// 0x4a
.type	_jmp_abs,		%function	// 0x4c
.type	_eor_abs,		%function	// 0x4d
.type	_lsr_abs,		%function	// 0x4e
.type	_bvc_rel,		%function	// 0x50
.type	_eor_ind_y,	%function	// 0x51
.type	_eor_zpg_x,	%function	// 0x55
.type	_lsr_zpg_x,	%function	// 0x56
.type	_cli_imp,		%function	// 0x58
.type	_eor_abs_y,	%function	// 0x59
.type	_eor_abs_x,	%function	// 0x5d
.type	_lsr_abs_x,	%function	// 0x5e
.type	_rts_imp,		%function	// 0x60
.type	_adc_x_ind,	%function	// 0x61
.type	_adc_zpg,		%function	// 0x65
.type	_ror_zpg,		%function	// 0x66
.type	_pla_imp,		%function	// 0x68
.type	_adc_imm,		%function	// 0x69
.type	_ror_a,		%function	// 0x6a
.type	_jmp_ind,		%function	// 0x6c
.type	_adc_abs,		%function	// 0x6d
.type	_ror_abs,		%function	// 0x6e
.type	_bvs_rel,		%function	// 0x70
.type	_adc_ind_y,	%function	// 0x71
.type	_adc_zpg_x,	%function	// 0x75
.type	_ror_zpg_x,	%function	// 0x76
.type	_sei_imp,		%function	// 0x78
.type	_adc_abs_y,	%function	// 0x79
.type	_adc_abs_x,	%function	// 0x7d
.type	_ror_abs_x,	%function	// 0x7e
.type	_sta_x_ind,	%function	// 0x81
.type	_sty_zpg,		%function	// 0x84
.type	_sta_zpg,		%function	// 0x85
.type	_stx_zpg,		%function	// 0x86
.type	_dey_imp,		%function	// 0x88
.type	_txa_imp,		%function	// 0x8a
.type	_sty_abs,		%function	// 0x8c
.type	_sta_abs,		%function	// 0x8d
.type	_stx_abs,		%function	// 0x8e
.type	_bcc_rel,		%function	// 0x90
.type	_sta_ind_y,	%function	// 0x91
.type	_sty_zpg_x,	%function	// 0x94
.type	_sta_zpg_x,	%function	// 0x95
.type	_stx_zpg_y,	%function	// 0x96
.type	_tya_imp,		%function	// 0x98
.type	_sta_abs_y,	%function	// 0x99
.type	_txs_imp,		%function	// 0x9a
.type	_sta_abs_x,	%function	// 0x9d
.type	_ldy_imm,		%function	// 0xa0
.type	_lda_x_ind,	%function	// 0xa1
.type	_ldx_imm,		%function	// 0xa2
.type	_ldy_zpg,		%function	// 0xa4
.type	_lda_zpg,		%function	// 0xa5
.type	_ldx_zpg,		%function	// 0xa6
.type	_tay_imp,		%function	// 0xa8
.type	_tax_imp,		%function	// 0xaa
.type	_lda_imm,		%function	// 0xa9
.type	_ldy_abs,		%function	// 0xac
.type	_lda_abs,		%function	// 0xad
.type	_ldx_abs,		%function	// 0xae
.type	_bcs_rel,		%function	// 0xb0
.type	_lda_ind_y,	%function	// 0xb1
.type	_ldy_zpg_x,	%function	// 0xb4
.type	_lda_zpg_x,	%function	// 0xb5
.type	_ldx_zpg_y,	%function	// 0xb6
.type	_clv_imp,		%function	// 0xb8
.type	_lda_abs_y,	%function	// 0xb9
.type	_tsx_imp,		%function	// 0xba
.type	_ldy_abs_x,	%function	// 0xbc
.type	_lda_abs_x,	%function	// 0xbd
.type	_ldx_abs_y,	%function	// 0xbe
.type	_cpy_imm,		%function	// 0xc0
.type	_cpm_x_ind,	%function	// 0xc1
.type	_cpy_zpg,		%function	// 0xc4
.type	_cpm_zpg,		%function	// 0xc5
.type	_dec_zpg,		%function	// 0xc6
.type	_iny_imp,		%function	// 0xc8
.type	_cmp_imm,		%function	// 0xc9
.type	_dex_imp,		%function	// 0xca
.type	_cpy_abs,		%function	// 0xcc
.type	_cmp_abs,		%function	// 0xcd
.type	_dec_abs,		%function	// 0xce
.type	_bne_rel,		%function	// 0xd0
.type	_cmp_ind_y,	%function	// 0xd1
.type	_cmp_zpg_x,	%function	// 0xd5
.type	_dec_zpg_x,	%function	// 0xd6
.type	_cld_imp,		%function	// 0xd8
.type	_cmp_abs_y,	%function	// 0xd9
.type	_cmp_abs_x,	%function	// 0xdd
.type	_dec_abs_x,	%function	// 0xde
.type	_cpx_imm,		%function	// 0xe0
.type	_sbc_x_ind,	%function	// 0xe1
.type	_cpx_zpg,		%function	// 0xe4
.type	_sbc_zpg,		%function	// 0xe5
.type	_inc_zpg,		%function	// 0xe6
.type	_inx_imp,		%function	// 0xe8
.type	_sbc_imm,		%function	// 0xe9
.type	_nop_imp,		%function	// 0xea
.type	_cpx_abs,		%function	// 0xec
.type	_sbc_abs,		%function	// 0xed
.type	_inc_abs,		%function	// 0xee
.type	_beq_rel,		%function	// 0xf0
.type	_sbc_ind_y,	%function	// 0xf1
.type	_sbc_zpg_x,	%function	// 0xf5
.type	_inc_zpg_x,	%function	// 0xf6
.type	_sed_imp,		%function	// 0xf8
.type	_sbc_abs_y,	%function	// 0xf9
.type	_sbc_abs_x,	%function	// 0xfd
.type	_inc_abs_x,	%function	// 0xfe
.type	_error_1,		%function	// 0xff


.thumb
.section .inst_lookup, "ax"

// ************************* get op codes ********************************
// pc is in r3 (6502 true, no emulator offset)must add __emu_start__ for 
// rp2040 address
.equ EMU_PROG_START, 	0x400
.equ LOWER_A,		0x00	// lowest 6502 acc reg to  trace
.equ UPPER_A,		0xff	// highest 6502 acc register to trace
.equ LOWER_R4,		0x00	// lowest 6502 r4 reg to trace
.equ UPPER_R4,		0xff	// highest 6502 r4 register to trace
.equ LOWER_R9,		0x00	// lowest 6502 r4 reg to  trace
.equ UPPER_R9,		0xff	// highest 6502 r4 register to trace
.equ TRACE_BOT,		0x4000	// lowest 6502 program count to trace
.equ TRACE_TOP, 	0x4000	// highest 6502 program count to trace
.equ PC_STOP, 		0x3466	// stop 6502 emulator at this PC
_clear_regs:
	ldr r3, =EMU_PROG_START	// initialize program counter r3
	mov r4, #0				// clear op code r4	
	mov r5, #0				// clear accumulator r5
	mov r6, #0				// clear processor status register
	mov r7, #0				// clear address register r7
	mov r8, r7 				// clear pc high (not really used)
	mov r9, r7 				// clear pc low (not really used)
	mov r10, r7				// clear X register r10
	mov r11, r7				// clear Y register r11
	mov r0, #0xff
	mov r12, r0				// start stack pointer at $ff
	adr r0, __6502_uart_base__		// get address of "__6502_uart_base__"
	ldr r2, __6502_uart_base__		// get value of "__6502_uart_base__"
	ldr r1, =__emu_start__
	add r1, r1, r2			// calculate global address of "__6502_uart_base__"	
	str r1, [r0]			// store global address of "__6502_uart_base__"
	ldr r0, =__6502_uart_base__	// pointer
	ldr r0, [r0]					// get value of 
	mov r1, #0
	strb	r1, [r0, #5]				// clear status register (0xe805)

_get_instr:
	ldr r0, =__emu_start__		// get start of 6502 memory
	add r0, r0, r3 				// RP2040 pc pointer is in r0
	ldrb r4, [r0, #0]			// get the op code
	ldrb r7, [r0, #1]			// get operand 1 (LSB)
	ldrb r1, [r0, #2]			// get operand 2 (MSB)
	lsl r1, #8					// shift MSB left 8
	add r7, r7, r1				// calculate address register (r7) HHLL

_lookup_inst:					// opcode in r4, shift 2 bits left, and then use
								// in lookup table "_vector_inst"
	lsl r4, #2					// shift opcode left 2 bits to multiply by 4
	ldr r0, =__lookup_start__	// get _lookup_table start address in r0
	ldr r1, [r0, r4]			// get address of instruction routines
	lsr r4, #2					// shift r4 back so the opcode is easy to see in printout
	blx r1						// branch to instruction routine	
//	bl trace					// print status for selected instructions
	b _get_instr				// get the next instruction
	
trace:
	push {lr}
	push {r1}				// r1 is memorialized here so r1 will be valid for printout
// This will only print for specific "r4" register values 
	ldr r1, =LOWER_R4		// checks for the lowest r4
	cmp r4, r1
	blt skip_print
	ldr r1, =UPPER_R4		// checks for the highest r4
	cmp r4, r1
	bgt skip_print
// This will only print for specific "r4" register values 
	ldr r1, =LOWER_R9		// checks for the lowest r4
	cmp r9, r1
	blt skip_print
	ldr r1, =UPPER_R9		// checks for the highest r4
	cmp r9, r1
	bgt skip_print	
// This will only print for specific "acc" register values 
	ldr r1, =LOWER_A		// checks for the lowest acc
	cmp r5, r1
	blt skip_print
	ldr r1, =UPPER_A		// checks for the highest acc
	cmp r5, r1
	bgt skip_print
// This will print registers for every instruction if PC is between TRACE_BOT & TRACE_TOP
	ldr r1, =TRACE_BOT		// checks for the lowest PC
	cmp r3, r1
	blt skip_print
	ldr r1, =TRACE_TOP		// checks for the highest PC
	cmp r3, r1
	bgt skip_print
	pop {r1}
	bl print_registers		// routine to print out emulator status
	b trace_ret
skip_print:
// This will stop at a particular PC value
	ldr r1, =PC_STOP		// load program counter line to stop at
	cmp r3, r1
	bne trace_pop_r1		// if continuing, then pop {r1} to clean up
	pop {r1}				// 
	bl print_registers		// routine to print out emulator status
	bl stop					// routine to stop the emulator
trace_pop_r1:
	pop {r1}
trace_ret:
	pop {pc}
	
/*
chk_char_out:	
// 	check for ready to send character from 6502
// routine to look at e805, bit 5
// and if character ready to send, grab value of 
// e801 and store to rp2040 uart0 data register.
	ldr r1, =__6502_uart_base__	//get pointer
	ldr r1, [r1]			// get value
	ldrb r0, [r1, #5]		// get value of 6502 uart SR
	mov r2, #0b00100000		// bit mask for bit 5
	and r0, r0, r2			// isolate bit 5 (set means ready to transmit)
	bne	send_char			// "UART" ready to transmit
	b _get_instr			// get the next instruction
send_char:	
	ldrb r0, [r1, #1]		// get character to transmit
	bl uart0_out			// transmit the character
	ldrb r0, [r1, #5]		// get the 6502 status register again
	bic r0, r2				// clear bit 5, if you are here, bit 5 of r2 is set
	strb r0, [r1, #5]		// store status register back (0xe805)
*/	
.align 4
.word	__emu_start__ 		// beginning of 6502 memory
.word	__lookup_start__ 	// beginning of Instr lookup table
__6502_uart_base__:
.word 	0xe800 				// base address for 6502 "uart"



.thumb
.section .inst_exec, "ax"
// ************************* instruction routines ************************

_lookup:

_brk_imp:	                        // 0x00
	     	push {lr}	
			bl print_registers	// routine to print out emulator status
			add r3, #2				// increment pc by 2
									// break address in r3
			mov r7,r3				// the break address (RAH, RAL) is loaded into r7
			lsr r7, #8				// shift break address right to get RAH in LSB
			bl _1_byte_push		// write r7 (RAH) to stack
			mov r7,r3				// reload the return address into r7 RAL in LSB
			bl _1_byte_push		// write r7 (RAL) to stack
			mov r7, #0b00110000	// bitmask to set brk and reserved flags
			orr r7, r7, r6			// combine all the flags
			bl _1_byte_push		// write break and reserved to stack,
			bl _sei_imp			// set the interupt disable flag
			bl load_int_vector	// change pc to interrupt vector
			pop {pc}	
_ora_x_ind:	                    // 0x01
	     	push {lr}
			bl _x_ind				// returns address of byte in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_ora_zpg:	                        // 0x05
	     	push {lr}
			bl _zpg					// returns zp address in r7
			bl _1_byte_read		// returns operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7			
	     	pop {pc}	
_asl_zpg:	                        // 0x06
	     	push {lr}	
	     	bl _zpg					// returns zp address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// returns operand in r7
			lsl r7, #1				// shift r7 left 1 bit
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
			pop {pc}	
_php_imp:	                        // 0x08
	     	push {lr}	
			bl _imp					// pc incrmented by 1, r7 cleared
			mov r7, r6				// load r7 with Processor Status register
			mov r1, #3				// 
			lsl r1, #4				// bit mask for "black magic" setting of bits 4 & 5
			orr r7, r7, r1			// this is undocumented in early 6502 books
			bl _1_byte_push		// write r7 into empty byte (pointed to by r1) in stack
	     	pop {pc}	
_ora_imm:	                        // 0x09
	     	push {lr}
			bl _imm					// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7			
	     	pop {pc}	
_asl_a:	                        // 0x0a
	     	push {lr}	
			bl _imp					// r7 cleared, pc incremented by 1
			lsl r5, #1				// shift accumulator left 1 bit
			mov r7, r5				// load r7 with new accumulator value
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			mov r0, #0xff			// least significant bit mask
			and r5, r5, r0			// get rid of bit 8 in accumulator
	     	pop {pc}	
_ora_abs:	                        // 0x0d
	     	push {lr}	
			bl _abs					// returns address of byte in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7			
	     	pop {pc}	
_asl_abs:	                        // 0x0e
	     	push {lr}	
	     	bl _abs					// returns address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// returns operand in r7
			lsl r7, #1				// shift r7 left 1 bit
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1			
	     	pop {pc}	
_bpl_rel:	                        // 0x10
	     	push {lr}	
			mov r1, #0x80			// set bit 7 of r1 (to isolate n flag)
			and r1, r1, r6			// test bit 7 of PSR
			beq _bpl_rel_1		// if bit 7 is cleared, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 7 is set, then return
  _bpl_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_ora_ind_y:			    		// 0x11
	     	push {lr}
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7			
	     	pop {pc}	
_ora_zpg_x:	                    // 0x15
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7			
	     	pop {pc}	
_asl_zpg_x:	                    // 0x16
	     	push {lr}	
	     	bl _zpg_x				// returns address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// returns operand in r7
			lsl r7, #1				// shift r7 left 1 bit
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1			
	     	pop {pc}	
_clc_imp:	                        // 0x18
	     	push {lr}
			bl _imp					// increment pc by 1, r7 cleared
			mov r1, #0b00000001	// set bit 1
			bic r6, r1				// clear bit 1
	     	pop {pc}	
_ora_abs_y:	                    // 0x19
	     	push {lr}
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7				
	     	pop {pc}	
_ora_abs_x:                      	// 0x1d
	     	push {lr}
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			orr r5, r5, r7			// or acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7				
	     	pop {pc}	
_asl_abs_x:                      	// 0x1e
	     	push {lr}
	     	bl _abs_x				// returns address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// returns operand in r7
			lsl r7, #1				// shift r7 left 1 bit
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1				
	     	pop {pc}	
_jsr_abs:	                        // 0x20
	     	push {lr}
			bl _abs					// get the address to jump to in r7, return address in r3
			push {r7}				// save address to jump to (r7) in the stack
			sub r3, #1				// subtract 1 to point to the last byte of the jsr instruction
			mov r7,r3				// the return address (RAH, RAL) is loaded into r7
			lsr r7, #8				// shift return address right to get RAH in LSB
			bl _1_byte_push		// write r7 (RAH) to stack
			mov r7,r3				// reload the return address into r7 RAL in LSB
			bl _1_byte_push		// write r7 (RAL) to stack
			pop {r7}				// restore the address to jump to
			mov r3, r7				// update the PC with the address to jump to
	     	pop {pc}	
_and_x_ind:                      	// 0x21
	     	push {lr}	
			bl _x_ind				// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7				
	     	pop {pc}	
_bit_zpg:	                        // 0x24
	     	push {lr}	
			bl _zpg					// address is in r7
			bl _1_byte_read		// operand is in r7
			mov r0, #0b11000000 	// bit mask for bits 6 & 7
			bic r6, r6, r0			// clear bits 6 & 7 of r6 (PSR)
			and r0, r0, r7			// isolate bits 6 & 7 of memory
			orr r6, r6, r0			// set bits 6 & 7 if appropriate
			and r7, r7, r5			// and accumulator with operand, leave accumulator unchanged
			bl _flag_z				// change z (z tested and updated)
			pop {pc}
	
_and_zpg:	                        // 0x25
	     	push {lr}	
			bl _zpg					// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7				
	     	pop {pc}	
_rol_zpg:	                        // 0x26
	     	push {lr}			
			bl _zpg					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// bit mask for carry flag
			lsl r7, r7, #1			// shift r7 left 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			add r7, r7, r0			// add carry bit to r7
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_plp_imp:	                        // 0x28
	     	push {lr}	
			bl _imp					// r7 is cleared
			bl _1_byte_pop		// loads r7 with last value on stack
			mov r6, r7				// loads value of r7 into PSR 
	     	pop {pc}	
_and_imm:	                        // 0x29
	     	push {lr}	
			bl _imm					// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7				
	     	pop {pc}	
_rol_a:		                    // 0x2a
	     	push {lr}	
			bl _a					// clear r7 and increments pc by 1
			mov r0, #0b00000001	// bit mask for bit 0
			lsl r5, r5, #1			// shift accumulator (r5) left 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			add r5, r5, r0			// if carry bit was set, add 1 to r7
			mov r7, r5				// copy accumulator into r7 for flag check
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			mov r0, #0xff			// least significant bit mask
			and r5, r5, r0			// get rid of bit 8 in accumulator
	     	pop {pc}

_bit_abs:							// 0x2c
			push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand is in r7
			mov r0, #0b11000000 	// bit mask for bits 6 & 7
			bic r6, r6, r0			// clear bits 6 & 7 of r6 (PSR)
			and r0, r0, r7			// isolate bits 6 & 7 of memory
			orr r6, r6, r0			// set bits 6 & 7 if appropriate
			and r7, r7, r5			// and accumulator with operand, leave accumulator unchanged
			bl _flag_z				// change n and z (bit 7 of r7 into n, z tested and updated)
			pop {pc}

_and_abs:	                        // 0x2d
	     	push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}		
_rol_abs:	                        // 0x2e
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// move PSR into r0 to isolate the carry bit
			lsl r7, r7, #1			// shift r7 left 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			add r7, r7, r0			// if carry bit was set, add 1 to r7
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_bmi_rel:	                        // 0x30
	     	push {lr}	
			mov r1, #0x80			// set bit 7 of r1 (to isolate n flag)
			and r1, r1, r6			// test bit 7 of PSR
			bne _bmi_rel_1		// if bit 7 is set, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 7 is cleared, then return
  _bmi_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}		
_and_ind_y:                      	// 0x31
	     	push {lr}	
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7	
	     	pop {pc}	
_and_zpg_x:                      	// 0x35
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7	
	     	pop {pc}	
_rol_zpg_x:                      	// 0x36
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// move PSR into r0 to isolate the carry bit
			lsl r7, r7, #1			// shift r7 left 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			add r7, r7, r0			// if carry bit was set, add 1 to r7
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_sec_imp:	                        // 0x38
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r0, #1
			orr r6, r6, r0			// set carry bit (bit 0)
	     	pop {pc}	
_and_abs_y:                      	// 0x39
	     	push {lr}	
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_and_abs_x:                      	// 0x3d
	     	push {lr}	
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			and r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_rol_abs_x:                      	// 0x3e
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// move PSR into r0 to isolate the carry bit
			lsl r7, r7, #1			// shift r7 left 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			add r7, r7, r0			// if carry bit was set, add 1 to r7
			bl _flag_nzc			// updates the n, z, and c flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_eor_x_ind:                      	// 0x41
	     	push {lr}	
			bl _x_ind				// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_rti_imp:	                        // 0x40
	     	push {lr}	
			bl _imp					// r7 is cleared, pc incremented by 1
			bl _1_byte_pop		// loads r7 with PSR on stack
			mov r6, r7				// loads value of r7 into PSR
			bl _1_byte_pop		// loads r7 with PCL on stack
			mov r0, r7				// stash PCL in r0
			bl _1_byte_pop		// loads r7 with PCH on stack
			lsl r7, #8				// shift PCH left 8 bits
			add r7, r7, r0			// add the PCH and PCL to get full pc in r7
			mov r3, r7				// restore pc to state before interrupt
	     	pop {pc}	
_eor_zpg:	                        // 0x45
	     	push {lr}	
			bl _zpg					// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// eor acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_lsr_zpg:	                        // 0x46
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// load bit 0 mask
			and r0, r0, r7			// isolate bit 0 into r0
			lsr r7, r7, #1			// shift r7 right 1 bit
			bl _flag_nzc			// updates the n, z, and c for new r7, c always cleared
			orr r6, r6, r0			// this will set c based on pre-shift bit 0
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}		
_pha_imp:	                        // 0x48
	     	push {lr}	
			bl _imp					// pc incremented by 1, r7 cleared
			mov r7, r5				// load r7 with accumulator (r5)
			bl _1_byte_push		// write r7 into empty byte (pointed to by r1) in stack
	     	pop {pc}	
_eor_imm:	                        // 0x49
	     	push {lr}	
			bl _imm					// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r0, #0xff			// bitmask for lsB
			and r5, r5, r0			// isolate lower 8 bits
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_lsr_a:		                    // 0x4a
	     	push {lr}	
			bl _a					// r7 cleared
			mov r0, #0b00000001	// load bit 0 mask
			and r0, r0, r5			// isolate bit 0 of accumulator (r5) into r0
			lsr r5, r5, #1			// shift accumulator (r5) right 1 bit
			mov r7, r5				// copy accumulator to r7 for flag check
			mov r7, r7				// load r7 with accumulator for flag check
			bl _flag_nzc			// updates the n, z, and c for new r7, c always cleared
			orr r6, r6, r0			// this will set c based on pre-shift bit 0
	     	pop {pc}	
_jmp_abs:	                        // 0x4c
	     	push {lr}	
			bl _abs					// address in r7
			mov r3, r7				// move address to pc
	     	pop {pc}	
_eor_abs:	                        // 0x4d
	     	push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_lsr_abs:	                        // 0x4e
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// load bit 0 mask
			and r0, r0, r7			// isolate bit 0 into r0
			lsr r7, r7, #1			// shift r7 right 1 bit
			bl _flag_nzc			// updates the n, z, and c for new r7, c always cleared
			orr r6, r6, r0			// this will set c based on pre-shift bit 0
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_bvc_rel:	                        // 0x50
	     	push {lr}	
			mov r1, #0b01000000	// set bit 6 of r1 (to isolate v flag)
			and r1, r1, r6			// test bit 6 of PSR
			beq _bvc_rel_1		// if bit 6 is cleared, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 6 is set, then return
  _bvc_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_eor_ind_y:                      	// 0x51
	     	push {lr}	
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_eor_zpg_x:                      	// 0x55
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_lsr_zpg_x:                      	// 0x56
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// load bit 0 mask
			and r0, r0, r7			// isolate bit 0 into r0
			lsr r7, r7, #1			// shift r7 right 1 bit
			bl _flag_nzc			// updates the n, z, and c for new r7, c always cleared
			orr r6, r6, r0			// this will set c based on pre-shift bit 0
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}		
_cli_imp:	                        // 0x58
	     	push {lr}
			bl _imp
			mov r1, #0b00000100	// set bit 2
			bic r6, r1				// clear bit 2
	     	pop {pc}	
_eor_abs_y:                      	// 0x59
	     	push {lr}	
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_eor_abs_x:                      	// 0x5d
	     	push {lr}	
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			eor r5, r5, r7			// and acumulator with operand
			mov r7, r5				// load r7 with accumulator for setting flags
			bl _flag_nz			// updates the n and z flags based on r7
	     	pop {pc}	
_lsr_abs_x:                      	// 0x5e
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			mov r0, #0b00000001	// load bit 0 mask
			and r0, r0, r7			// isolate bit 0 into r0
			lsr r7, r7, #1			// shift r7 right 1 bit
			bl _flag_nzc			// updates the n, z, and c for new r7, c always cleared
			orr r6, r6, r0			// this will set c based on pre-shift bit 0
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_rts_imp:	                        // 0x60
	     	push {lr}				
			bl _imp					// r7 is cleared
			bl _1_byte_pop		// loads r7 with PCL on stack
			mov r0, r7				// stash PCL in r0
			bl _1_byte_pop		// loads r7 with PCH on stack
			lsl r7, #8				// shift PCH left 8 bits
			add r7, r7, r0			// add the PCH and PCL to get full pc in r7
			add r7, r7, #1			// add 1 to get the next pc 
			mov r3, r7				// restore pc to state before interrupt
	     	pop {pc}	
_adc_x_ind:                      	// 0x61
	     	push {lr}
			bl _x_ind				// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
			pop {pc}
_adc_zpg:	                        // 0x65
	     	push {lr}	
			bl _zpg					// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_ror_zpg:	                        // 0x66
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			bl _ror					// operand in r7, address to write to in r1
	     	pop {pc}	
_pla_imp:	                        // 0x68
	     	push {lr}	
			bl _imp					// r7 is cleared
			bl _1_byte_pop		// loads r7 with last value on stack
			mov r5, r7				// loads value of r7 into acc 
			bl _flag_nz			// update the n and z flags
	     	pop {pc}	
_adc_imm:	                        // 0x69
	     	push {lr}	
			bl _imm					// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_ror_a:		                    // 0x6a
	     	push {lr}	
			bl _a					// r7 cleared
			mov r7, r5				// operand in r7
			mov r2, r7				// memorialize operand in r2
			mov r0, #0b00000001	// mask for carry flag
			and r2, r2, r0			// isolate bit 0 of operand, will set carry at end
			lsr r7, r7, #1			// shift r7 right 1 bit
			and r0, r0, r6			// isolate bit 0 of the processor status register
			lsl r0, #7				// shift the carry bit to bit 7	
			orr r7, r7, r0			// if carry bit was set, set bit 7 of r7 
			bl _flag_nz			// updates the n and z flags based on r7
			mov r0, #0b00000001	// mask for carry flag
			bic r6, r0				// clear carry flag 
			orr r6, r6, r2			// if bit 0 of r2 is set, then set carry flag
			mov r5, r7				// load accumulator (r5) with result (r7)
	     	pop {pc}	
_jmp_ind:	                        // 0x6c
	     	push {lr}	
			bl _ind					// address in r7
			mov r3, r7				// move address to pc			
	     	pop {pc}	
_adc_abs:	                        // 0x6d
	     	push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_ror_abs:	                        // 0x6e
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			bl _ror					// operand in r7, address to write to in r1
	     	pop {pc}	
_bvs_rel:	                        // 0x70
	     	push {lr}	
			mov r1, #0b01000000	// set bit 6 of r1 (to isolate v flag)
			and r1, r1, r6			// test bit 6 of PSR
			bne _bvs_rel_1		// if bit 6 is set, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 6 is set, then return
  _bvs_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_adc_ind_y:                      	// 0x71
	     	push {lr}	
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_adc_zpg_x:                      	// 0x75
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_ror_zpg_x:                      	// 0x76
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			bl _ror					// operand in r7, address to write to in r1
	     	pop {pc}	
_sei_imp:	                        // 0x78
	     	push {lr}	
			bl _imp					// clears r7
			mov r0, #0b00000100	// bit mask for I flag
			orr r6, r6, r0			// set the I flag
	     	pop {pc}	
_adc_abs_y:                      	// 0x79
	     	push {lr}	
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_adc_abs_x:                      	// 0x7d
	     	push {lr}	
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _adc					// do the addition
	     	pop {pc}	
_ror_abs_x:                      	// 0x7e
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			bl _ror					// operand in r7, address to write to in r1
	     	pop {pc}	
_sta_x_ind:                      	// 0x81
	     	push {lr}	
			bl _x_ind				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sty_zpg:	                        // 0x84
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r11				// move y register (r11) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sta_zpg:	                        // 0x85
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_stx_zpg:	                        // 0x86
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r10				// move x register (r10) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_dey_imp:	                        // 0x88
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r7, r11				// load r11 into r7 (can't work on r11 directly, thumb mode)
			sub r7, #1				// subtract 1 from r7
			mov r0, #0xff			// bitmask for lsB
			and r7, r7, r0			// isolate lower 8 bits
			mov r11, r7				// put new data in y register
			bl _flag_nz			// update z and n flags
	     	pop {pc}	
_txa_imp:	                        // 0x8a
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r5, r10				// transfer x (r10) into accumulator (r5)
			mov r7, r10				// load r7 with data to check flags
			bl _flag_nz			// update z and n flags
	     	pop {pc}	
_sty_abs:	                        // 0x8c
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r11				// move y register (r11) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sta_abs:	                        // 0x8d
	     	push {lr}				
			bl _abs					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_stx_abs:	                        // 0x8e
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r10				// move x register (r10) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_bcc_rel:	                        // 0x90
	     	push {lr}	
			mov r1, #0b00000001	// set bit 0 of r1 (to isolate c flag)
			and r1, r1, r6			// test bit 0 of PSR
			beq _bcc_rel_1		// if bit 0 is cleared, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 0 is set, then return
  _bcc_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_sta_ind_y:	                    // 0x91
	     	push {lr}	
			bl _ind_y				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sty_zpg_x:                      	// 0x94
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r11				// move y register (r11) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sta_zpg_x:                      	// 0x95
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_stx_zpg_y:                      	// 0x96
	     	push {lr}	
			bl _zpg_y				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r10				// move x register (r10) into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_tya_imp:	                        // 0x98
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r5, r11				// transfer y (r11) into accumulator (r5)
			mov r7, r11				// load r7 with data to check flags
			bl _flag_nz			// update z and n flags
	     	pop {pc}	
_sta_abs_y:                      	// 0x99
	     	push {lr}	
			bl _abs_y				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_txs_imp:	                        // 0x9a
	     	push {lr}	
			bl _imp					// no operand, pc inc by 1
			mov r12, r10			// move x reg. to 
	     	pop {pc}
_sta_abs_x:                      	// 0x9d
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// move address into r1 for prep to write
			mov r7, r5				// move accumulator into r7 in prep for write
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_ldy_imm:	                        // 0xa0
	     	push {lr}
			bl _imm					// operand in r7
			mov r11, r7				// move operand into r11
			bl _flag_nz
	     	pop {pc}	
_lda_x_ind:                      	// 0xa1
	     	push {lr}
			bl _x_ind				// address in r7		
			bl _1_byte_read		// operand in r7
			mov r5, r7				// move operand into r5
			bl _flag_nz
	     	pop {pc}	
_ldx_imm:	                        // 0xa2
	     	push {lr}
			bl _imm					// operand in r7
			mov r10, r7				// move operand into r10			
			bl _flag_nz
	     	pop {pc}	
_ldy_zpg:	                        // 0xa4
	     	push {lr}
			bl _zpg					// address in r7		
			bl _1_byte_read		// operand in r7
			mov r11, r7				// move operand into r11			
			bl _flag_nz
	     	pop {pc}	
_lda_zpg:	                        // 0xa5
	     	push {lr}
			bl _zpg					// address in r7		
			bl _1_byte_read		// operand in r7
			mov r5, r7				// move operand into r5			
			bl _flag_nz
	     	pop {pc}	
_ldx_zpg:	                        // 0xa6
	     	push {lr}
			bl _zpg					// address in r7		
			bl _1_byte_read		// operand in r7
			mov r10, r7				// move operand into r10			
			bl _flag_nz
	     	pop {pc}	
_tay_imp:	                        // 0xa8
	     	push {lr}	
			bl _imp					// no operand, pc inc by 1
			mov r11, r5				// move accumulator (r5) to y reg. (r11)
			mov r7, R11				// prep for flag check
			bl _flag_nz
	     	pop {pc}	
_tax_imp:	                        // 0xaa
	     	push {lr}	
			bl _imp					// no operand, pc inc by 1
			mov r10, r5				// move accumulator (r5) to x reg. (r10)
			mov r7, r10 			// prep for flag check
			bl _flag_nz
	     	pop {pc}	
_lda_imm:	                        // 0xa9
	     	push {lr}
			bl _imm					// operand in r7
			mov r5, r7				// moves operand into r5
			bl _flag_nz
	     	pop {pc}	
_ldy_abs:	                        // 0xac
	     	push {lr}
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			mov r11, r7				// moves operand into r11
			bl _flag_nz
	     	pop {pc}	
_lda_abs:	                        // 0xad
	     	push {lr}
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			mov r5, r7				// moves r7 into r5
			bl _flag_nz
	     	pop {pc}	
_ldx_abs:	                        // 0xae
	     	push {lr}
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			mov r10, r7				// moves operand into r10
			bl _flag_nz
	     	pop {pc}	
_bcs_rel:	                        // 0xb0
	     	push {lr}	
			mov r1, #0b00000001	// set bit 0 of r1 (to isolate c flag)
			and r1, r1, r6			// test bit 0 of PSR
			bne _bcs_rel_1		// if bit 0 is set, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 0 is set, then return
  _bcs_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_lda_ind_y:                      	// 0xb1
	     	push {lr}
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			mov r5, r7				// moves operand into r5
			bl _flag_nz
	     	pop {pc}	
_ldy_zpg_x:                      	// 0xb4
	     	push {lr}
			bl _zpg_x				// zpage address in r7
			bl _1_byte_read		// operand in r7
			mov r11, r7				// moves operand into r11
			bl _flag_nz
	     	pop {pc}	
_lda_zpg_x:                      	// 0xb5
	     	push {lr}
			bl _zpg_x				// zpage address in r7
			bl _1_byte_read		// operand in r7
			mov r5, r7				// moves operand into r5					
			bl _flag_nz
	     	pop {pc}	
_ldx_zpg_y:                      	// 0xb6
	     	push {lr}
			bl _zpg_y				// zpage address in r7
			bl _1_byte_read		// operand in r7
			mov r10, r7				// moves operand into r10				
			bl _flag_nz
	     	pop {pc}	
_clv_imp:	                        // 0xb8
	     	push {lr}
			bl _imp					// r7 cleared, pc incremented by 1
			mov r1, #0b01000000	// set bit 6
			bic r6, r1				// clear bit 6			
	     	pop {pc}	
_lda_abs_y:                      	// 0xb9
	     	push {lr}
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			mov r5, r7				// move operand into r5
			bl _flag_nz
	     	pop {pc}	
_tsx_imp:	                        // 0xba
	     	push {lr}
			bl _imp					// no operand, pc inc by 1
			mov r10, r12			// move stack pointer into x reg.
			mov r7, r10 			// prep for checking flags
			bl _flag_nz
	     	pop {pc}	
_ldy_abs_x:                      	// 0xbc
	     	push {lr}
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			mov r11, r7				// move operand into r11			
			bl _flag_nz
	     	pop {pc}	
_lda_abs_x:                      	// 0xbd
	     	push {lr}
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			mov r5, r7				// move operand into r5			
			bl _flag_nz
	     	pop {pc}	
_ldx_abs_y:                      	// 0xbe
	     	push {lr}
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			mov r10, r7				// move operand into r10			
			bl _flag_nz
	     	pop {pc}	
_cpy_imm:	                        // 0xc0
	     	push {lr}	
			bl _imm					// operand in r7
			bl _cpy					// set n, z, c flags
	     	pop {pc}	
_cpm_x_ind:                      	// 0xc1
	     	push {lr}	
			bl _x_ind				// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_cpy_zpg:	                        // 0xc4
	     	push {lr}	
			bl _zpg					// address in r7 
			bl _1_byte_read		// operand in r7
			bl _cpy					// set n, z, c flags
	     	pop {pc}	
_cpm_zpg:	                        // 0xc5
	     	push {lr}	
			bl _zpg					// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_dec_zpg:	                        // 0xc6
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			sub r7, r7, #1			// subtract 1 from operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1	
	     	pop {pc}	
_iny_imp:	                        // 0xc8
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r7, r11				// move y reg to r7 (can't work on r11 directly (thumb)
			add r7, r7, #1			// add 1 to the operand
			mov r0, #0xff			// bitmask for lsB
			and r7, r7, r0			// isolate lower 8 bits
			bl _flag_nz			// updates the n and z flags based on r7
			mov r11, r7  			// move new value back to y reg (r11)
	     	pop {pc}	
_cmp_imm:	                        // 0xc9
	     	push {lr}	
			bl _imm					// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_dex_imp:	                        // 0xca
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r7, r10				// load r10 into r7 (can't work on r10 directly, thumb mode)
			sub r7, #1				// subtract 1 from r7
			mov r0, #0xff			// bitmask for lsB
			and r7, r7, r0			// isolate lower 8 bits
			mov r10, r7				// put new data in x register
			bl _flag_nz			// update z and n flags
	     	pop {pc}	
_cpy_abs:	                        // 0xcc
	     	push {lr}	
			bl _abs					// address in r7 
			bl _1_byte_read		// operand in r7
			bl _cpy					// set n, z, c flags
	     	pop {pc}	
_cmp_abs:	                        // 0xcd
	     	push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7+
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_dec_abs:	                        // 0xce
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			sub r7, r7, #1			// subtract 1 from operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_bne_rel:	                        // 0xd0
	     	push {lr}				
			mov r1, #0b00000010	// set bit 1 of r1 (to isolate z flag)
			and r1, r1, r6			// test bit 1 of PSR
			beq _bne_rel_1		// if bit 1 is cleared, then perform branch
			bl _imm					// increment pc by 1
			pop {pc}				// if bit 1 is set, then return
  _bne_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_cmp_ind_y:                      	// 0xd1
	     	push {lr}	
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_cmp_zpg_x:                      	// 0xd5
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_dec_zpg_x:                      	// 0xd6
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			sub r7, r7, #1			// subtract 1 from operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_cld_imp:	                        // 0xd8
	     	push {lr}	
			bl _imp					// pc increments by 1, r7 cleared
			mov r1, #0b00001000	// set bit 3
			bic r6, r1				// clear bit 3	
	     	pop {pc}	
_cmp_abs_y:                      	// 0xd9
	     	push {lr}	
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_cmp_abs_x:                      	// 0xdd
	     	push {lr}	
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _cmp					// set n, z, c flags
	     	pop {pc}	
_dec_abs_x:                      	// 0xde
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			sub r7, r7, #1			// subtract 1 from operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_cpx_imm:	                        // 0xe0
	     	push {lr}	
			bl _imm					// operand in r7
			bl _cpx					// set n, z, c flags
	     	pop {pc}	
_sbc_x_ind:                      	// 0xe1
	     	push {lr}	
			bl _x_ind				// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_cpx_zpg:	                        // 0xe4
	     	push {lr}	
			bl _zpg					// address in r7 
			bl _1_byte_read		// operand in r7
			bl _cpx					// set n, z, c flags
	     	pop {pc}	
_sbc_zpg:	                        // 0xe5
	     	push {lr}	
			bl _zpg					// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_inc_zpg:	                        // 0xe6
	     	push {lr}	
			bl _zpg					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			add r7, r7, #1			// add 1 to the operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_inx_imp:	                        // 0xe8
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r7, r10				// move x reg to r7 (can't work on r10 directly (thumb)
			add r7, r7, #1			// add 1 to the operand	
			mov r0, #0xff			// bitmask for lsB
			and r7, r7, r0			// isolate lower 8 bits
			bl _flag_nz			// updates the n and z flags based on r7
			mov r10, r7  			// move new value back to x reg (r10)
	     	pop {pc}	
_sbc_imm:	                        // 0xe9
	     	push {lr}	
			bl _imm					// operand in R7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_nop_imp:	                        // 0xea
	     	push {lr}	
			bl _imp					// clears r7 and nothing else
	     	pop {pc}	
_cpx_abs:	                        // 0xec
	     	push {lr}	
			bl _abs					// address in r7 
			bl _1_byte_read		// operand in r7
			bl _cpx					// set n, z, c flags
	     	pop {pc}	
_sbc_abs:	                       	// 0xed
	     	push {lr}	
			bl _abs					// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_inc_abs:	                        // 0xee
	     	push {lr}	
			bl _abs					// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			add r7, r7, #1			// add 1 to the operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_beq_rel:	                        // 0xf0
	     	push {lr}	
			mov r1, #0b00000010	// set bit 1 of r1 (to isolate z flag)
			and r1, r1, r6			// test bit 1 of PSR
			bne _beq_rel_1		// if bit 1 is set, then perform branch
			bl _imm					// increment pc by 2
			pop {pc}				// if bit 1 is set, then return
  _beq_rel_1:
			bl _rel					// calculate the new pc and store in r3
	     	pop {pc}	
_sbc_ind_y:                      	// 0xf1
	     	push {lr}	
			bl _ind_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_sbc_zpg_x:                      	// 0xf5
	     	push {lr}	
			bl _zpg_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_inc_zpg_x:                      	// 0xf6
	     	push {lr}	
			bl _zpg_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			add r7, r7, #1			// add 1 to the operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_sed_imp:	                        // 0xf8
	     	push {lr}	
			bl _imp					// r7 cleared
			mov r0, #0b00001000	// bit 3 mask to isolate d flag
			orr r6, r6, r0			// set bit 3 (d flag)
	     	pop {pc}	
_sbc_abs_y:                      // 0xf9
	     	push {lr}	
			bl _abs_y				// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_sbc_abs_x:                      	// 0xfd
	     	push {lr}	
			bl _abs_x				// address in r7
			bl _1_byte_read		// operand in r7
			bl _sbc					// subtract acc (r5) = acc (r5) - operand (r7)
	     	pop {pc}	
_inc_abs_x:                      	// 0xfe
	     	push {lr}	
			bl _abs_x				// address in r7
			mov r1, r7				// memorialize address in r1
			bl _1_byte_read		// operand in r7
			add r7, r7, #1			// add 1 to the operand		
			bl _flag_nz			// updates the n and z flags based on r7
			bl _1_byte_write		// write 1 byte in lsB of r7 into address r1
	     	pop {pc}	
_error_1:	                        // 0xff
	     	push {lr}	
			bl print_registers	// print emulator Status
	_error_1_1:		
			b _error_1_1			// and hold
	     	pop {pc}	

// ************************Addressing routines *****************************
// r3 holds the 6502 program counter (16 bits).  It is based on the 6502 address (6502 true)
// i.e. it does not have the offset to address the ARM area allocated to the 
// emulated 6502 memory.  	
// r7 is the address register.  That is used to load, store, or hold operands.
// addresses held in r7 are also 6502 true, i.e. no offset to ARM sram.

_abs:					// absolute Address in r7, increment pc by 3
	push {lr}
	add r3, #3				// increment pc by 3		
	pop {pc}

_imm:					// immediate Operand 1 in r7 LSB, increment pc by 2
	push {lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	add r3, #2				// increment pc by 2
	pop {pc}
	
_a:						// Accumulator no operand(clear r7), increment pc by 1
	push {lr}
	mov r7, #0				// clear r7
	add r3, #1				// increment pc by 1
	pop {pc}
	
_abs_x:				// Absolute x, add X reg to address reg (r7), increment pc by 3
	push {lr}
	add r7, r7, r10			// add X reg (r10) to address reg (r7)
	add r3, #3				// increment r3 by 3
	pop {pc}
	
_abs_y:				// Absolute Y, add Y reg to address reg (r7), increment pc by 3
	push {lr}
	add r7, r7, r11			// add Y reg (r11) to address reg (r7)
	add r3, #3				// increment r3 by 3
	pop {pc}
	
_imp:					// implied, clear r7 and increment pc by 1
	push {lr}
	mov r7, #0				// clear r7
	add r3, #1				// increment pc by 1
	pop {pc}

_ind:					// indirect, r7 = address held in the memory pointer by operands 1 & 2 in r7
	push {r0, lr}			// increment pc by 3
	bl _2_byte_read		// get 2 bytes in HHLL format from location pointed to by r7 
	add r3, #3				// increment pc by 3
	pop {r0, pc}
	
_x_ind:				// x indexed indirect AR (r7) = zpage address (operand 1 +x & operand 1 +x +1)
	push {r0, r1, lr}			// and increment pc by 2
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	add r7, r7, r10			// calculate z page address ( operand 1 + X)
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	bl _2_byte_read		// get 2 bytes in HHLL format from zero page in r7 
	add r3, #2				// increment pc by 2
	pop {r0, r1, pc}
	
_ind_y:				// indirect, y indexed r7 = zero page address contents plus y register, inc pc by 2
	push {r0, r1, lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	bl _2_byte_read		// get indirect 2 byte address pointed to by r7 (zpage)
	mov r0, r11				// move r11 into r0 (can't add r11 directly - thumb)
	add r7, r7, r0			// add y register to address in r7
	add r3, #2				// increment pc by 2
	pop {r0, r1, pc}
	
_rel:					// branch target is pc + r7 (1 byte, signed) 
							// bit 7 determines direction (set is backwards)
	push {r0, r1, lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsB
	add r3, #2				// increment pc to start of next instruction	
	mov r1, #0b10000000		// load bit mask to check for bit 7 cleared
	and r1, r1, r7			// isolate bit 7
	bne _rel_back			// bit 7 set, branch to backwards calculation
	add r3, r7, r3			// calculate branch, new pc = operand 1 (r7) plus pc
	pop {r0, r1, pc}		// return
_rel_back:	
	mov r1, #1
	lsl r1, #8				// load 0x100 base
	sub r1, r1, r7			// get the negative offset in r1
	sub r3, r3, r1			// calculate the new pc 
	pop {r0, r1, pc}		// return
	
_zpg:					// zero page address , r7 unchanged, increment pc by 2	
	push {r1, lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	add r3, #2				// increment pc by 2		
	pop {r1, pc}	
	
_zpg_x:				// zpage, x indexed r7 holds zpage address 
	push {r1, lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsb
	add r7, r7, r10			// add the x register
	and r7, r1				// remove the carry
	add r3, #2				// increment pc by 2
	pop {r1, pc}

_zpg_y:				// zpage, y indexed r7 holds zpage address
	push {r1, lr}
	mov r1, #0xff
	and r7, r7, r1			// isolate lsB
	add r7, r7, r11			// add the y register
	and r7, r1				// remove the carry 
	add r3, #2				// increment pc by 2
	pop {r1, pc}
	
// **********************common instruction routines ******************
_adc:							// operand in r7, will modify r5 and r7
		push {lr}
		mov r0, #0b00001000	// Decimal bit mask
		and r0, r0, r6			// isolate decimal flag
		bne _adc_bcd			// branch to BCD addition			
		mov r1, r5				// stash accumulator in r1 for v flag check
		add r5, r5, r7			// add operand (r7) and accumulator (r5)		
		mov r0, #0b00000001	// carry flag bit mask
		and r0, r0, r6			// isolate carry flag (bit 0)		
		add r5, r5, r0			// add the carry
		bl _flag_v				// update v flag
		mov r7, r5				// move accumulator r5 to r7 for flag check
		bl _flag_nzc			// updates the n, z, and c for r7
		mov r0, #0xff			// least significant bit mask
		and r5, r5, r0			// get rid of bit 8 in accumulator
		pop {pc}				// return from binary addition
  _adc_bcd:					// bcd addition
		mov r1, #0b00001111	// lower nibble mask
		push {r4}				// stash op code in stack to free up r4
		push {r5, r7}		   	// save accumulator and operand to stack
		and r5, r5, r1			// isolate lower nibble of Accumulator
		and r7, r7, r1			// isolate lower nibble of operand
		add r5, r5, r7			// add accumulator and operand
		mov r0, #0b00000001	// carry bit flag mask
		and r0, r6				// isolate carry bit
		add r5, r0				// add carry bit
		cmp r5, #10				// compare to 10
		bge _adc_bcd_1		// if >= 10, branch to carry set
		mov r0, #0				// there is no carry so clear r0
		b _adc_bcd_2
  _adc_bcd_1:		
		mov r0, #0b00010000	// carry bit flag mask to add to most sig. nibble
		sub r5, r5, #10			// since greater than 10, subtract 10
  _adc_bcd_2:		
		mov r4, r5				// stash lower nibble of result in r4
		pop {r5, r7}			// restore accumulator and operand
		bic r5, r1				// clear lower nibble of accumulator
		bic r7, r1				// clear lower nibble of operand
		add r5, r5, r7			// add upper nibbles
		add r5, r5, r0			// add carry from lower nibble calc to upper nibble
		mov r0, #0b00000001	// carry bit flag mask
		bic r6, r0				// clear carry
		cmp r5, #0xa0			// compare to 160
		blt _adc_bcd_3		// if less than 160 branch to no carry
		sub r5, #0xa0			// convert to bcd
		orr r6, r6, r0			// set the carry bit
  _adc_bcd_3:
		orr r5, r5, r4			// "add" the lower nibble back in
		mov r0, #0xff			// least significant bit mask
		and r5, r5, r0			// get rid of bit 8 in accumulator
		mov r7, r5				// prep for flag check, operand in r7
		bl _flag_nz			// update the N and Z flags
		pop {r4}				// restore op code
		pop {pc}				// and return
	
_cmp:							// compare accumulator, operand in r7
	push {lr}	
	mov r0, #0b00000001		// carry bit mask
//	cmp r5, r7 					// compare accumulator and operand
	cmp r7, r5 					// compare accumulator and operand
//	bge _cmp_1					// if r5 > r7 then branch to set C
	ble _cmp_1					// if r7 <= r5 then branch to set C
	sub r7, r5, r7				// accumulator - operand => r7
	mov r2, #0xff				// least significant bit mask
	and r7, r7, r2				// get rid of bit 8 in r7 before testing flags
	bl _flag_nz				// update n and z flags on value in r7 
	bic r6, r0					// clear carry flag
	pop {pc}					
 _cmp_1:	
	sub r7, r5, r7				// accumulator - operand => r7
	mov r2, #0xff				// least significant bit mask
	and r7, r7, r2				// get rid of bit 8 in r7 before testing flags
	bl _flag_nz				// update n and z flags on value in r7 
	orr r6, r0					// set carry flag
	pop {pc}
_cpx:
	push {lr}	
	mov r0, #0b00000001			// carry bit mask
	mov r1, r10					// load x reg into r1
	cmp r1, r7 					// compare x reg and operand
	bge _cpx_1					// if r5 >= r7 then branch to set C
	sub r7, r1, r7				// accumulator - operand => r7
	mov r2, #0xff				// least significant bit mask
	and r7, r7, r2				// get rid of bit 8 in r7 before testing flags
	bl _flag_nz					// update n and z flags on value in r7 
	bic r6, r0					// clear carry flag
	pop {pc}					
 _cpx_1:	
	sub r7, r1, r7				// accumulator - operand => r7
	mov r2, #0xff				// least significant bit mask
	and r7, r7, r2				// get rid of bit 8 in r7 before testing flags
	bl _flag_nz					// update n and z flags on value in r7 
	orr r6, r0					// set carry flag
	pop {pc}
_cpy:
	push {lr}	
	mov r0, #0b00000001			// carry bit mask
	mov r1, r11					// load y reg into r1
	cmp r1, r7 					// compare y reg and operand
	bge _cpy_1					// if r5 >= r7 then branch to set C
	sub r7, r1, r7				// accumulator - operand => r7
	bl _flag_nz					// update n and z flags on value in r7 
	bic r6, r0					// clear carry flag
	pop {pc}					
 _cpy_1:	
	sub r7, r1, r7				// accumulator - operand => r7
	bl _flag_nz					// update n and z flags on value in r7 
	orr r6, r0					// set carry flag
	pop {pc}

_ror:							// operand in r7, address to write to in r1
	push {lr}	
	mov r2, r7					// memorialize operand in r2
	mov r0, #0b00000001			// mask for carry flag
	and r2, r2, r0				// isolate bit 0 of operand, will set carry at end
	lsr r7, r7, #1				// shift r7 right 1 bit
	and r0, r0, r6				// isolate bit 0 of the processor status register
	lsl r0, #7					// shift the carry bit to bit 7	
	orr r7, r7, r0				// if carry bit was set, set bit 7 of r7 
	bl _flag_nz					// updates the n and z flags based on r7
	mov r0, #0b00000001			// mask for carry flag
	bic r6, r0					// clear carry flag 
	orr r6, r6, r2				// if bit 0 of r2 is set, then set carry flag
	bl _1_byte_write			// write 1 byte in lsB of r7 into address r1
	pop {pc}
_rti:
	push {lr}	
	pop {pc}
_rts:
	push {lr}	
	pop {pc}
_sbc:
	push {r3, r4, r7, lr}					// operand in r7
	mov r0, #0b00001000				// Decimal bit mask
		and r0, r0, r6				// isolate decimal flag
		bne _sbc_bcd				// branch to BCD addition	
// binary subtraction	
		mov r0, #0b00000001	// carry flag bit mask 
		mov r2, #0xff			// mask for eor
		and r0, r0, r6			// isolate carry flag (bit 0)
		mov r1, r5				// load r1 with pre-op accumulator for overflow check
		eor r7, r7, r2			// one's complement of r7
		mov r4, r7				// memorialize one's compliment operand in r7 for v flag check
		add r4, r4, r0			// work on r4, add in carry
		add r5, r5, r4			// perform two's complement subtraction
		mov r0, #0b11000011	// mask to clear n, v, z, and c flags
		bic	r6, r0				// clear n, v, z, and c flags
		bl _flag_v				// r1 =pre-op acc, r7 = operand (ones complement) , r5 = post-op acc (all unchanged)
		mov r7, r5				// load r7 with acc for flag_nzc check
		bl _flag_nzc			// operand in r7
		and r5, r5, r2			// only use the lsB
		pop {r3, r4, r7, pc}	// return from binary add, pre-op operand in r9, pre-op flags in r8, 
								// and pre-op accumulator in r1
		
  _sbc_bcd:					// bcd subtraction (uses 10's complement)
		push {r5, r7}			// memorialize acc and original operand
		mov r0, #9				// store 9 for 9's complement math
		mov r2, #0b1111			// bit mask for lower nibble
		and r5, r5, r2			// get lower nibble of accumulator
		and r7, r7, r2			// get lower nibble of operand
		mov r4, #1				// bit mask for carry flag
		and r4, r6, r4			// get carry flag
		sub r7, r0, r7 			// subtract operand from 9 (9's complement)
		add r5, r5, r7 			// perform the 9's commplement "subtraction"
		add r5, r5, r4 			// add the carry for full 10's complement "subtraction"
		mov r4, r5				// store the "pre-compared to 10" result in r4 for carry
		cmp r5, #10				// is it a valid bcd digit?
		blt _sbc_bcd_1			// yes, no correction needed
		add r5, r5, #6			// otherwise add 6
		mov r4, r5				// store the bcd corrected result in r4 for carry
  _sbc_bcd_1:		
		mov r1, r5				// stash lower nibble of result in r1
		and r1, r1, r2			// isolate only the lower nibble in r1
		pop {r5, r7}			// restore original acc and operand
		lsr r5, #4				// move upper nibble to lower nibble location
		lsr r7, #4				// move upper nibble to lower nibble location
		lsr r4, #4				// move carry from last operation to bit 0
		sub r7, r0, r7 			// subtract operand from 9 (9's complement)
		add r5, r5, r7 			// perform the 9's commplement "subtraction"
		add r5, r5, r4 			// add the carry for full 10's complement "subtraction"
		mov r4, r5				// store the "pre-compared to 10" result in r4 for carry
		cmp r5, #10				// is it a valid bcd digit?
		blt	_sbc_bcd_2			// yes, no correction needed
		add r5, r5, #6			// otherwise add 6)
		mov r4, r5				// store the bcd corrected result in r4 for carry
  _sbc_bcd_2:		
		and r5, r5, r2			// isolate only the lower nibble in r5
		lsl r5, #4				// move nibble back to where it belongs (upper nibble)
		add r5, r5, r1 			// add lower nibble result to upper nibble
		lsr r4, #4				// shift carry bit to bit 0
		mov r0, #1				// bit mask for carry flag
		bic r6, r0				// first clear the carry flag
		orr r6, r6, r4			// and then set the carry flag as needed
		mov r7, r5				// prep for n and z flag check
		bl _flag_nz			// check the n and z flags
		pop {r3, r4, r7, pc}	// and return
	
// ********************** flag routines *************************
_flag_z:				// set z if bits 0 through 7 are all zero
	push {r0, r1, lr}
	mov r1, #0x02
	mov r0, #0xff		// lsB mask
	and r0, r0, r7		// keep only 8 lsb
	cmp r0, #0
	beq _flag_z_1		// bits are zero so set r6, bit 1
	bic r6, r6, r1		// clear bit 1, r6
	pop {r0, r1, pc}
_flag_z_1:
	orr r6, r6, r1		// set bit 1, r6
	pop {r0, r1, pc}
		
_flag_nz:				// assigns negative and zero flags, operand in r7
						// r7 unchanged
	push {r0, r1, lr}
	mov r0, #0x80		// set n if bit 7 of r7 is set
	bic r6, r6, r0		// clear the n flag
	and r0, r0, r7		// isolate bit 7	
	orr r6, r6, r0		// if bit 7 is set then set n flag
						// set z if bits 0 through 7 are all zero
	mov r1, #2			// mask for bit 1 (zero flag)
	mov r0, #0xff		// lsB mask
	and r0, r0, r7		// keep only 8 lsb
	beq _flag_nz_3		// bits are zero so set r6, bit 1
	bic r6, r6, r1		// clear bit 1, r6
	pop {r0, r1, pc}
_flag_nz_3:
	orr r6, r6, r1		// set bit 1, r6
	pop {r0, r1, pc}

_flag_nzc:				// assigns negative, zero, and carry flag, result in r7
						// bit 8 of r7 sets the carry bit, (r0, r1, r7 unchanged)
	push {r0, r1, lr}	
	bl _flag_nz			// sets the n and z flags
	mov r0, r7			// r0 holds the operand
	mov r1, #01			// 
	bic r6, r1			// clear carry flag
	lsl r1, #8			// bit 8 bit mask
	and r1, r1, r7		// isolate bit 8 of r7
	lsr r1, #8			// move carry bit back to bit 0
	orr r6, r1			// if bit 8 of r7 is set, then set carry flag (r6, bit 0)
	pop {r0, r1, pc}

_flag_v:				// r1 is pre-op accumulator, r7 is operand, r5 is post-op accumulator
						// if bit 7 of both pre-op acc and operand are 0, result (bit 7) must be 0
						// if bit 7 of both pre-op acc and operand are 1, result (bit 7) must be 1
						// otherwise, overflow occured so set v
	push {r1, r5, r7, lr}
	mov r0, #0b10000000	// bitmask for bit 7
	and r1, r1, r0			// isolate bit 7s for all
	and r5, r5, r0
	and r7, r7, r0
	cmp r1, r7				// compare bit 7, pre-op acc and operand
	beq _flag_v_1			// if they are equal, check for overflow
	mov r0, #0b01000000	// bitmask for bit 6 (v flag)
	bic	r6, r0				// since not equal, clear v flag
	pop {r1, r5, r7, pc}	// if not equal,then return
_flag_v_1:	
	mov r0, #0b01000000	// bitmask for bit 6 (v flag)
	cmp r1, r5				// compare pre-op and post-op accumulator bit 7
	bne _flag_v_2			// if not equal, then set v flag
	bic	r6, r0				// if equal, clear v flag
	pop {r1, r5, r7, pc}	// then return 
_flag_v_2:
	orr r6, r6, r0			// set v flag
	pop {r1, r5, r7, pc}	// return
	
						

					 
	 

	 
// **********************other subroutines***************************
// These routines convert between the 6502 true address and the RP2040 memory map
// __emu_start__ is the symbol for the start of the 6502 emulator RAM, this comes 
// from the linker script.			

_2_byte_read:			// 6502 address in r7, returns 2 successive bytes in r7
						// in the form of HHLL, this applies the offset for the 
						// RP2040 address map
	push {r0, r1, r2, lr}
	ldr r0, =__emu_start__	// get start of 6502 memory
	ldrb r1, [r0, r7]			// load LSB into r1
	add r7, #1					// increment address pointer
	ldrb r2, [r0, r7]			// load MSB into r2
	lsl r2, #8					// shift MSB left 8 bits
	add r1, r1, r2				// combine into r1 in the form HHLL
	mov r7, r1					// move new address into r7
	pop {r0, r1, r2, pc}
	
_1_byte_read:			// 6502 address in r7, returns 1 byte in r7
						// in the form of LL, this applies the offset for the 
						// RP2040 address map
	push {r0, r1, lr}
	ldr r0, =__emu_start__	// get start of 6502 memory 
	ldrb r1, [r0, r7]			// load LSB into r1
	mov r7, r1          		// move single byte into r7
	pop {r0, r1, pc}
	
_1_byte_write:			// 6502 address in r1, byte to write in r7
						// This applies the offset for the RP2040 address map
						// r7 & r1 unchanged
	push {r0, lr}
	ldr r0, =__emu_start__		// get start of 6502 memory
	strb r7, [r0, r1]
	pop {r0, pc}	
	
_1_byte_pop:				// pops 1 byte off stack, result in r7, increments sp	
	push {r0, r1, lr}
	mov r7, r12					// loads stack pointer address into r7
	add r7, #1					// increment stack pointer
	mov r0, #0xff				// lsB mask
	and r7, r7, r0				// keep only 8 lsb
	mov r12, r7					// updates stack pointer
	mov r0, #1					// load one 
	lsl r0, #8					// shift for bit mask for bit 9 (0x0100)
	add r7, r7, r0				// add the start of page 0ne to sp to get absolute address
	ldr r0, =__emu_start__		// get start of 6502 memory
	ldrb r1, [r0, r7]			// load LSB into r1
	mov r7, r1          		// move single byte into r7
	pop {r0, r1, pc}
	
_1_byte_push:			// data to push onto stack in R7, sp is decremented after push
	push {r0, lr}
	mov r1, r12					// load r1 with SP (points to next empty spot)
	mov r0, #1					// load one 
	lsl r0, #8					// shift for bit mask for bit 8 (0x0100)
	add r1, r1, r0				// add the start of page 0ne to sp to get absolute address		
	ldr r0, =__emu_start__		// get start of 6502 memory
	strb r7, [r0, r1]			// store r7 into emulator sram page one
	sub r1, r1, #1				// decrement SP address by 1 (point to next empty spot)
	mov r0, #0xff				// lsB mask
	and r1, r1, r0				// keep only 8 lsb
	mov r12, r1					// update the SP in r12
	pop {r0, pc}

.align 4
.word	__emu_start__ 		// beginning of 6502 memory
.word	__lookup_start__ 	// beginning of Instr lookup table

// ****************** routines to load various vector addresses into r3
load_int_vector:
		push {lr}
		ldr r1, =int_vector	// store interrupt vector into r0
		ldr r0, =__emu_start__		// get start of 6502 memory
		add r0, r0, r1			// get the location of the int vector
		ldrb r3, [r0, #1]		// get the Vector High
		lsl r3, #8				// and shift over 8 bits
		ldrb r1, [r0, #0]		// get Vector Low
		add r3, r3, r1			// and add to make new pc
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



.word __6502_uart_base__ 	// base address for 6502 "uart"

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
		
.end


