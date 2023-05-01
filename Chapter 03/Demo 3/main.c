// BMA03 Demo 3 echoing keyboard using C functions to initalize the UART 
// but using the UART registers directly to check for and handle the data.
//This is is a helper program to initalize the UART and to get the assembly program started
#include <stdio.h>
#include "pico/stdlib.h"

void start();

int main()
	{
	stdio_uart_init();	// can also be used, check dis file, stdio_init_all just calls stdio_uart_init
	start();
	}
