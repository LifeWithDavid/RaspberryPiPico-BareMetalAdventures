# Makefile: Life with David-BMA04

CC=arm-none-eabi-gcc
MACH=cortex-m0plus
CFLAGS= -c -mcpu=$(MACH) -mthumb -std=gnu11 -Wall -O0 
LFLAGS= -nostdlib -T BMA04_ls.ld -Wl,-Map=final.map

all:  bs2_default_padded_checksummed.o assembly.o vector_table_BMA04.o

assembly.o:assembly.s
	$(CC) $(CFLAGS) -o $@ $^

bs2_default_padded_checksummed.o:bs2_default_padded_checksummed.S	
	$(CC) $(CFLAGS) -o $@ $^
	
vector_table_BMA04.o:vector_table_BMA04.S
	$(CC) $(CFLAGS) -o $@ $^		
	
final.elf:bs2_default_padded_checksummed.o vector_table_BMA04.o assembly.o 
	$(CC) $(LFLAGS) -o $@ $^
clean:
	-del -f $(wildcard *.o)  
	-del -f $(wildcard *.elf) 
	-del -f $(wildcard *.uf2)
	-del -f $(wildcard *.map)
	
link: final.elf

uf2: 
	elf2uf2 final.elf final.uf2
	