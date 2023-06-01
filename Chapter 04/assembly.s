//bare metal assembly blinking routine
//Life with David - BMA Chapter 04
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


// set the control	
	ldr r0, =ctrl		// control register for GPIO25
	mov r1, #5			// Function 5, select SIO for GPIO25 2.19.2
	str r1, [r0]  		// Store function_5 in GPIO25 control register
//shifts over "1" the number of bits of GPIO pin	
	mov r1, #1			// load a 1 into register 1
	lsl r1, r1, #25 	// move the bit over to align with GPIO25
	ldr r0, =sio_base	// SIO base 
	str r1, [r0, #36]  	// 0x20 GPIO output enable

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

.equ rst_clr, 0x4000f000 	// atomic register for clearing reset controller 2.1.2
	
.equ rst_base, 0x4000c000	// reset controller base 2.14.3

.equ ctrl, 0x400140cc 	// GPIO25_CTRL 2.19.6.1
	
.equ sio_base, 0xd0000000	// SIO base 2.3.1.7

.equ big_num, 0x00f00000 	// large number for the delay loop
	
