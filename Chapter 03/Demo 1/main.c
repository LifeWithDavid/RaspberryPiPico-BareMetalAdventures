//BMA03_Demo 1 demo Character I/O using UART with C

#include <stdio.h>
#include "pico/stdlib.h"


int main(){
	stdio_init_all();   //Initialize the UART in C
	char ch;  			
// loop to grab character keyboard and then echo it on terminal
	while (true) {
		ch = getchar();
		putchar(ch);
	}
}