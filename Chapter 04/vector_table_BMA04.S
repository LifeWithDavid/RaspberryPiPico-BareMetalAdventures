// Vector Table; Life with David-BMA04
// Hard coded version of vector table to be loaded at 0x10000100

.cpu cortex-m0plus
.thumb

.section .vectors, "ax"

.word	0x20042000	//start of stack pointer
.word	0x10000201	//reset
.word	0x100001c3	//isr_nmi
.word	0x100001c5	//isr_hardfault
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c7	//isr_svcall
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c1	//isr_invalid; Reserved, should never fire
.word	0x100001c9	//isr_pendsv
.word	0x100001cb	//isr_systick
.word	0x100001cd	//interrupt_0
.word	0x100001cd	//interrupt_1
.word	0x100001cd	//interrupt_2
.word	0x100001cd	//interrupt_3
.word	0x100001cd	//interrupt_4
.word	0x100001cd	//interrupt_5
.word	0x100001cd	//interrupt_6
.word	0x100001cd	//interrupt_7
.word	0x100001cd	//interrupt_8
.word	0x100001cd	//interrupt_9
.word	0x100001cd	//interrupt_10
.word	0x100001cd	//interrupt_11
.word	0x100001cd	//interrupt_12
.word	0x100001cd	//interrupt_13
.word	0x100001cd	//interrupt_14
.word	0x100001cd	//interrupt_15
.word	0x100001cd	//interrupt_16
.word	0x100001cd	//interrupt_17
.word	0x100001cd	//interrupt_18
.word	0x100001cd	//interrupt_19
.word	0x100001cd	//interrupt_20
.word	0x100001cd	//interrupt_21
.word	0x100001cd	//interrupt_22
.word	0x100001cd	//interrupt_23
.word	0x100001cd	//interrupt_24
.word	0x100001cd	//interrupt_25
.word	0x100001cd	//interrupt_26
.word	0x100001cd	//interrupt_27
.word	0x100001cd	//interrupt_28
.word	0x100001cd	//interrupt_29
.word	0x100001cd	//interrupt_30
.word	0x100001cd	//interrupt_31

