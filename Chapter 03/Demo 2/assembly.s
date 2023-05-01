//BMA03 Demo 2 echoing keyboard using C functions inside assembly program

.global start
start:

comm_loop:
	bl getchar			// Gets character from C function and puts it in r0
	bl putchar			// sends character in r0 to C function 
	b comm_loop		// branches back to the beginning
	