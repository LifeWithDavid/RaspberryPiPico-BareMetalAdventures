// BMA03 Demo 4 Bare Metal UART initalize, receive, and transmit
// Manipulate the RP2040 registers directly to intialize the clock, UART and GPIO.
// Also includes some LED debugging tools.

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
	
// *****************************************
// This sets up the UART to communicate

// checks if xosc is stable
xosc_stable:
	ldr r0, =xosc_rw	  	// base for xosc clock 
	ldr r1, [r0, #0x04]	  	// load xosc status XOSC: STATUS offset 4
	lsr r1, #31			  	// get rid of all bits but xosc stable
	beq xosc_stable	  	// if not stable then check again

// connect the xosc to GPIO 21 so we can measure its frequency "Function 8" 2.19.2
config_gpout0:
	ldr r0, =clk_rw   		// Base for clocks register
	mov r1, #0x45 	  		// load in 0b1000101 to enable and select xosc
	lsl r1, r1, #5	  		// shift over 5 bits to enable the clock generator
	str r1, [r0,#0]		  	// store in CLK_GPOUT0_CTRL (...100010100000)	
	ldr r0, =iob0a_rw	  	// base address iobank_0a 0x40014080	2.19.6.1
	mov r1, #8			  	// function 8 CLOCK GPOUT0        	2.19.2
	str r1, [r0, #0x2c]	  	// store function 8 in GPIO21_CTRL  	2.19.6.1

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
	mov r2, r1		  		// move bitmask from r1 into r2 (bit 22 set)
uartrst:     
	ldr r0, =rst_base	  	// base address for reset controller
	ldr r1, [r0, #8]   		// offset to get to the reset_done register
	and r1, r1, r2			// isolate bit 22
	beq uartrst   			// if bit 22 is 0 then check again, if not, reset is done
	
//Set peripheral clock 2.15.7 assumes sdk has already started xosc
set_peri_clk:
	ldr r0, =clk_rw   		// Base for clocks register
	mov r1, #1 		  		// load in first bit
	lsl r1, r1, #11	  		// shift over 11 bits to enable the clock generator
	add r1, #128	  		// add 0b10000000 to select the crystal ocsillator
	str r1, [r0,#0x48]    	// store in clk_peri_ctrl (...100010000000)	

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
	
// set word length (8 bits) and enable FIFOs UARTLCR_H 4.2.8
set_word_len:
	mov r1, #112			// 0b01110000 = 112 (UARTLCR_H) (112 with fifos enabled)
	str r1, [r0, #0x02c]  	// store in UARTLCR_H

// Connect UART0 on iobank_0 pads 0 and 1 using "Function 2"   2.19.2
config_uart_gpio:
	ldr r0, =iob0_rw	  	//base address iobank_0 			2.19.6.1
	mov r1, #2			  	// function 2 UART0_TX & UART0_RX  2.19.2
	str r1, [r0, #4]  		//store function 2 in GPIO0_CTRL  2.19.6.1
	str r1, [r0, #0x0c]    //store function 2 in GPIO1_CTRL  2.19.6.1	

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
	bne uart0_in_loop	 	// if RX FIFO is empty, go back and check again
	ldr r0, [r1, #0] 		// load data from uart data register into r0, UARTDR
	pop {r1,r2,r3,pc}		//return
	
// Debug subroutines
//shifts over "1" the number of bits of GPIO pin
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
	
led_loop:
	str r6, [r5, #20] 	// 0x14 GPIO output value set (turn on led)
	ldr r3, =big_num	// load countdown number
	bl delay 			// branch to subroutine delay
	
	str r6, [r5, #24]	// 0x18 GPIO output value clear (turn off led)
	ldr r3, =big_num	// load countdown number
	bl delay 			// branch to subroutine delay
	
	b led_loop			// do the loop again

delay:
	push {r3,lr}		// save link register on stack
	ldr r3, =big_num
dly_loop:	
	sub r3, #1			// subtract 1 from register 3
	bne dly_loop		// loop back to dly_loop if not zero
	pop {r3,pc}			// return from subroutine

data:	

.equ clk_rw, 	0x40008000 // Clocks register 2.15.7

.equ rst_base,	0x4000c000	// reset controller base 2.14.3

.equ rst_set, 	0x4000e000 // atomic register for setting reset controller 2.1.2

.equ rst_clr, 	0x4000f000 // atomic register for clearing reset controller 2.1.2

.equ iob0_rw, 	0x40014000	// iobank_0 base address 2.19.6.1

.equ iob0a_rw,	0x40014080 // iobank_0 base address starting at GPIO16 2.19.6.1

.equ ctrl,   	0x400140cc // GPIO25_CTRL 2.19.6.1

.equ xosc_rw, 	0x40024000 // Base for xosc 2.16.7

.equ uart0_rw,	0x40034000	// UART0 register base address 4.2.8
	
.equ sio_base, 0xd0000000	// SIO base 2.3.1.7

.equ big_num, 	0x00f00000 // large number for the delay loop

.equ lil_num,  	0x000000f0 // Little number for the delay loop


	
