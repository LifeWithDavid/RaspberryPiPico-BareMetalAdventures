//bare metal assembly clocks
//Life with David - BMA Chapter 05 - Demo 4 - Setting Crystal Oscillator

.section .reset, "ax"
.global start
start:

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
						// 0x4 for ROSC source, 0x5 for XOSC source, 0x6 for clk_sys
						// 0xa for clk_ref
	lsl r1, r1, #5		// move over to bit 5
	str r1, [r0, #0x00]	//store in CLOCKS: CLK_GPOUT0_CTRL 2.15.7
	ldr r0, = clck_aset// load in clock atomic set register base
	mov r1, #1			// load in 1 bit
	lsl r1, r1, #11		// shift over 11 bits to enable CLOCKS: CLK_GPOUT0_CTRL
	str r1, [r0, #0x00]	// store clock enable bit in CLOCKS: CLK_GPOUT0_CTRL atomic set reg
	
//releases the peripheral reset for iobank_0
	ldr r0, =rst_clr	// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #32      	// load a 1 into bit 5
	str r1, [r0, #0] 	// store the bitmask into the atomic register to clear register

// check if reset is done
rst:     
    ldr r0, =rst_base	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #32			// load 1 in bit 5 of register 2 (...0000000000100000)
	and r1, r1, r2		// isolate bit 5
	beq rst				// if bit five is 0 then check again, if not, reset is done
// Route xosc to gpout0 2.19.2 and 2.15.7 (CLK_GPOUT0_CTRL, GPIO21)
	ldr r0, =ctrl_gp21
	mov r1, #8			// function to tie CLK_GPOUT0_CTRL to GPIO21 2.19.2
	str r1, [r0]		// Store function_8 in GPIO21 control register 2.19.6.1
//shifts over "1" the number of bits of GPIO pin	
	mov r1, #1			// load a 1 into register 1
	lsl r1, r1, #21 		// move the bit over to align with GPIO21
	ldr r0, =sio_base	// SIO base 2.3.1.7
	str r1, [r0, #0x24]	// 0x24 GPIO output enable

// set the control	
	ldr r0, =ctrl_gp04	// control register for GPIO04
	mov r1, #5			// Function 5, select SIO for GPIO04 2.19.2
	str r1, [r0]  		// Store function_5 in GPIO04 control register
//shifts over "1" the number of bits of GPIO pin	
	mov r1, #1			// load a 1 into register 1
	lsl r1, r1, #4 		// move the bit over to align with GPIO04
	ldr r0, =sio_base	// SIO base 2.3.1.7
	str r1, [r0, #0x24]	// 0x24 GPIO output enable

led_loop:
	str r1, [r0, #20] 	// 0x14 GPIO output value set
	ldr r3, =big_num	// load countdown number
	bl delay 			// branch to subroutine delay
	
	str r1, [r0, #24]	// 0x18 GPIO output value clear
	ldr r3, =big_num	// load countdown number
	bl delay 			// branch to subroutine delay
	
	b led_loop			// do the loop again

delay:
	sub r3, #1			// subtract 1 from register 3
	bne delay			// loop back to delay if not zero
	bx lr				// return from subroutine
	
	mov r0, r0          // to word align data below
	
.data	
.equ rosc_freq,	0x00fabfa0 	// base for rosc frequency range, add 4 through 8

.equ rst_clr, 	0x4000f000 	// atomic register for clearing reset controller 2.1.2
	
.equ rst_base, 	0x4000c000	// reset controller base 2.14.3

.equ ctrl_gp04,	0x40014024 	// GPIO04_CTRL 2.19.6.1

.equ ctrl_gp21,	0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL

.equ clck_base,	0x40008000	// Clock register base address

.equ clck_aset,	0x4000a000	// Clock atomic set

.equ rosc_base,	0x40060000	// Ring oscillator base 2.17.8

.equ rosc_aset,	0x40062000 	// Ring oscillator atomic set register

.equ xosc_base,	0x40024000	// XOSC Base address

.equ xosc_aset,	0x40026000	// XOSC atomic set

.equ xosc_en,	0x00fab000	// enable for xosc

.equ rosc_pw, 	0x96960000 	// ring oscillator password 2.17.8

.equ rosc_powr,	0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
	
.equ sio_base, 	0xd0000000	// SIO base 2.3.1.7

.equ big_num, 	0x000f0000 	// large number for the delay loop
