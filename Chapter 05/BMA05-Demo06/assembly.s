//bare metal assembly clocks
//Life with David - BMA Chapter 05 - Demo 6 - using external clocks

.section .reset, "ax"
.global start
start:

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
// Route external clock to gpin1 2.19.2 and 2.15.7 (CLK_GPIN1_CTRL, GPIO22)
	ldr r0, =ctrl_gp22
	mov r1, #8			// function to tie CLK_GPIN1_CTRL to GPIO22 2.19.2
	str r1, [r0]		// Store function_8 in GPIO22 control register 2.19.6.1

// switch the clock source from default rosc to gpin1
	ldr r0, =clck_base // load in clock registers base address
	mov r1, #0x41		// selects the gpin1 for the ref clock 
	str r1, [r0, #0x30]	// save it in CLOCKS: CLK_REF_CTRL 2.15.7
	mov r1, #0			// selects the ref clock for the system clock 
	str r1, [r0, #0x3c]	// save it in CLOCKS: CLK_SYS_CTRL 2.15.7	

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
.equ rosc_freq,	0x00fabfa0	// base for rosc frequency range, add 4 through 8

.equ rst_clr, 		0x4000f000	// atomic register for clearing reset controller 2.1.2
	
.equ rst_base, 	0x4000c000	// reset controller base 2.14.3

.equ ctrl_gp04,	0x40014024 // GPIO04_CTRL 2.19.6.1

.equ ctrl_gp21,	0x400140ac	// GPIO21_CTRL 2.19.6.1 for CLK_GPOUT0_CTRL

.equ ctrl_gp22,	0x400140b4	// GPIO22_CTRL 2.19.6.1 for CLK_GPIN1_CTRL

.equ clck_base,	0x40008000	// Clock register base address

.equ clck_aset,	0x4000a000	// Clock atomic set

.equ rosc_base,	0x40060000	// Ring oscillator base 2.17.8

.equ rosc_aset,	0x40062000 // Ring oscillator atomic set register

.equ xosc_base,	0x40024000	// XOSC Base address

.equ xosc_aset,	0x40026000	// XOSC atomic set

.equ xosc_en,		0x00fab000	// enable for xosc

.equ rosc_pw, 		0x96960000 // ring oscillator password 2.17.8

.equ rosc_powr,	0x96960000	// Full strength for rosc FREQA and FREQB 2.17.8
	
.equ sio_base, 	0xd0000000	// SIO base 2.3.1.7

.equ big_num, 		0x000f0000 // large number for the delay loop
	