// BMA03 Demo 2 echoing keyboard using C functions
// This is is just a helper program to get the assembly program started
// and to initialize the standard I/O
#include <stdio.h>
#include "pico/stdlib.h"

void start();

int main()
	{
	stdio_init_all();  // needed to clear io registers
	start();
	}
