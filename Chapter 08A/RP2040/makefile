# Makefile: Life with David-BMA08A hellorld

CC=arm-none-eabi-gcc
MACH=cortex-m0plus
CFLAGS= -c -mcpu=$(MACH) -mthumb -std=gnu11 -Wall -O0 
LFLAGS= -nostdlib -T BMA08_ls.ld -Wl,-Map=final.map
UF2=elf2uf2 final.elf final.uf2
DIS=arm-none-eabi-objdump -D final.elf > final.dis

all:  bs2_default_padded_checksummed.o assembly.o vector_table_BMA07.o

assembly.o:assembly.s
	$(CC) $(CFLAGS) -o $@ $^

bs2_default_padded_checksummed.o:bs2_default_padded_checksummed.S	
	$(CC) $(CFLAGS) -o $@ $^
	
vector_table_BMA07.o:vector_table_BMA07.S
	$(CC) $(CFLAGS) -o $@ $^		
	
final.elf:bs2_default_padded_checksummed.o vector_table_BMA07.o assembly.o 
	$(CC) $(LFLAGS) -o $@ $^
	
final.uf2: final.elf
	$(UF2) -o $@ $^

final.dis:final.elf
	$(DIS) 
	

clean:
	-del -f $(wildcard *.o)  
	-del -f $(wildcard *.elf) 
	-del -f $(wildcard *.uf2)
	-del -f $(wildcard *.map)
	-del -f $(wildcard *.dis)
	
link: final.elf

uf2: final.uf2 

dis: final.dis
 
full: clean uf2 dis
