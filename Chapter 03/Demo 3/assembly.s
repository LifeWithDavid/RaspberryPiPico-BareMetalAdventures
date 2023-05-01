// BMA03 Demo 3 echoing keyboard using C functions to initalize the UART 
// but using the UART registers directly to check for and handle the data.
// Also includes some LED blink debugging tools.

.global start
start:

//  ****************************** 
// This sets up the LED to blink as a debugging tool
//Bring iobank_0 out of reset (deassert the reset) 
	ldr r0, =rst_clr  		// atomic register for clearing reset controller (0x4000c000+0x3000) 
	mov r1, #32        		// load a 1 into bit 5
	str r1, [r0, #0]   		// store the bitmask into the atomic register to clear register

// check if iobank_0 is deasserted
iobank0_rst:     
    ldr r0, =rst_base	  	// base address for reset controller
	ldr r1, [r0, #8] 	  	// offset to get to the reset_done register
	mov r2, #32			  	// load 1 in bit 5 of register 2 (...0000000000100000)
	and r1, r1, r2		  	// isolate bit 5
	beq iobank0_rst	  	// if bit five is 0 then check again, if not, reset is done
	
// set the control register to blink GPIO25
	ldr r0, =ctrl		  	// control register for GPIO25
	mov r1, #5			  	// Function 5, select SIO for GPIO25 2.19.2
	str r1, [r0]  		  	// Store function_5 in GPIO25 control register

// Communications test loop
comm_test_loop:

	bl uart0_in
	bl uart0_out
	b comm_test_loop

uart0_out:					// data out in r0
	push {r1,r2,r3,lr}
uart0_out_loop:	
	ldr r1, =uart0_rw 		// base address for uart0 registers
	ldr r2, [r1, #0x18]		// read UART0 flag register UARTFR 4.2.8
	mov r3, #32				// mask for bit 5, TX FIFO full TXFF
	and r2, r3				// isolate bit 5
	bne uart0_out_loop		// if TX FIFO is full, go back and check again
	mov r2, #0xff			// bit mask for the 8 lowest bits
	and r0, r2				// get rid of all but the lowest 8 bits of data
	str r0, [r1, #0]		// store data in uart data register, UARTDR
	pop {r1,r2,r3,pc}	 	// return
	
uart0_in:
	push {r1,r2,r3,lr}
uart0_in_loop:	
	ldr r1, =uart0_rw 	 	// base address for uart0 registers
	ldr r2, [r1, #0x18] 	// read UART0 flag register UARTFR 4.2.8
	mov r3, #16		 		// mask for bit 4, RX FIFO empty RXFE
	and r2, r3		 		// isolate bit 4
	bne uart0_in_loop		// if RX FIFO is empty, go back and check again
	ldr r0, [r1, #0] 		// load data from uart data register into r0, UARTDR
	pop {r1,r2,r3,pc}		 		//return
	
// Debug subroutines
led_on:
	push {r5,r6,lr}		 	// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =sio_base  // SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #20]  	// 0x14 GPIO output value set
	pop {r5,r6,pc}		 	// return from subroutine
	
led_off:
	push {r5,r6,lr}		 	// save link register on stack
	mov r6, #1		 	// load a 1 into register 6
	lsl r6, r6, #25  	// move the bit over to align with GPIO25
	ldr r5, =sio_base 	// SIO base 
	str r6, [r5, #36]  	// 0x20 GPIO output enable
	str r6, [r5, #24] 	// 0x18 GPIO output value clear
	pop {r5,r6,pc}		 	// return from subroutine	

data:	
.equ clk_rw, 	0x40008000 // Clocks register 2.15.7
.equ rst_base,	0x4000c000 // reset controller base 2.14.3
.equ rst_set, 	0x4000e000 // atomic register for setting reset controller 2.1.2
.equ rst_clr, 	0x4000f000 // atomic register for clearing reset controller 2.1.2
.equ iob0_rw, 	0x40014000 // iobank_0 base address 2.19.6.1
.equ iob0a_rw,	0x40014080 // iobank_0 base address starting at GPIO16 2.19.6.1
.equ ctrl,   	0x400140cc // GPIO25_CTRL 2.19.6.1
.equ xosc_rw, 	0x40024000 // Base for xosc 2.16.7
.equ uart0_rw,	0x40034000 // UART0 register base address 4.2.8
.equ sio_base, 0xd0000000 // SIO base 2.3.1.7
