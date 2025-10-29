/* BMA17-Demo 3: This program sends the number of the control key function to an 
   assembly program using the multi-core FIFO register.  The assembly program returns the keycode 
   to the C program using the multi-core FIFO registerthat then prints out the result to the terminal.
   The assembly program uses an interrupt.*/

.cpu cortex-m0plus
.thumb
.thumb_func

.global sio_irq_handler

.section .my_asm_prgm, "ax"
.global asm_entry
.thumb_func
//bare metal assembly blinking routine
//This was originally F:\Users\pico\Downloads\pico assembly\first_asm_demo1

    .extern multicore_fifo_push_blocking
    .extern multicore_fifo_pop_blocking

asm_entry:

//releases the peripheral reset for iobank_0
	ldr r0, =RST_CLR	// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #32      	// load a 1 into bit 5
	str r1, [r0, #0] 	// store the bitmask into the atomic register to clear register

// check if reset is done
rst:     
    ldr r0, =RST_BASE	// base address for reset controller
	ldr r1, [r0, #8] 	// offset to get to the reset_done register
	mov r2, #32			// load 1 in bit 5 of register 2 (...0000000000100000)
	and r1, r1, r2		// isolate bit 5
	beq rst				// if bit five is 0 then check again, if not, reset is done
// set the control	
	ldr r0, =CTRL		// control register for GPIO25
	mov r1, #5			// Function 5, select SIO for GPIO25 2.19.2
	str r1, [r0]  		// Store function_5 in GPIO25 control register
//shifts over "1" the number of bits of GPIO pin	
	mov r1, #1			// load a 1 into register 1
	lsl r1, r1, #25 	// move the bit over to align with GPIO25
	ldr r0, =SIO_BASE	// SIO base 
	str r1, [r0, #36]  	// 0x20 GPIO output enable
	
// Blink LED about 4 Hz
led_loop:
	str r1, [r0, #20] 	// 0x14 GPIO output value set
	bl short_delay 			// branch to subroutine delay	
	str r1, [r0, #24]	// 0x18 GPIO output value clear
	bl short_delay 			// branch to subroutine delay	
	b led_loop			// do the loop again

.thumb_func

    //---------------------------------------------------
    // Assembly ISR for SIO (inter-core FIFO)
    //---------------------------------------------------
sio_irq_handler:
    push {r0-r3, lr}          // Save registers
	bl multicore_fifo_pop_blocking  //get info from core 1 fifo
	bl multicore_fifo_push_blocking //send into to core 1 fifo
	bl led_count
	pop {r0-r3, pc}           // Restore registers and return


led_count:  				// blinks GPIO25 the number of times that is in r0 
	push {r0-r3, lr}
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
	pop {r0-r3, pc}

delay:
	push {r3, lr}
	ldr r3, =BIG_NUM	// load countdown number
	b delay_loop
short_delay:
    push {r3, lr}
	ldr r3, =LIL_NUM	// load smaller countdown number	
delay_loop:
	sub r3, #1			// subtract 1 from register 3
	bne delay_loop		// loop back to delay if not zero
	pop {r3, pc}		    // return from subroutine	
	
led_on:
	push {r5,r6,lr}		// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =SIO_BASE  // SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #20]  	// 0x14 GPIO output value set
	pop {r5,r6,pc}		// return from subroutine
	
led_off:
	push {r5,r6,lr}		// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =SIO_BASE 	// SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #24] 	// 0x18 GPIO output value clear
	pop {r5,r6,pc}		// return from subroutine

two_long_blinks:
	push {r0-r3, lr}
	bl delay
	bl delay
	bl delay
	bl led_on
	bl delay
	bl delay
	bl led_off
	bl delay
	bl delay
	bl led_on
	bl delay
	bl delay
	bl led_off	
	pop {r0-r3, pc}	
	
one_very_long_blink:
	bl delay
	bl delay
	bl delay
	bl delay
	bl led_on
	bl delay
	bl delay	
	bl delay
	bl delay
	bl led_off

data:	

	.equ RST_CLR,  0x4000f000 	// atomic register for clearing reset controller 2.1.2
	.equ RST_BASE, 0x4000c000	// reset controller base 2.14.3
	.equ CTRL,     0x400140cc 		// GPIO25_CTRL 2.19.6.1
	.equ SIO_BASE, 0xd0000000	// SIO base 2.3.1.7
	.equ BIG_NUM,  0x00f00000 	// larger number for the function blinking
	.equ LIL_NUM,  0x00400000 	// smaller number for the blinking loop






