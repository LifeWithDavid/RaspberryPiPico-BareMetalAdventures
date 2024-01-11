# Makefile: Life with David-BMA11
#*********makefile for compiling and linking the RP2040 emulator program and including 6502 program*************
CC=arm-none-eabi-gcc
MACH=cortex-m0plus
CFLAGS= -c -mcpu=$(MACH) -mthumb -std=gnu11 -Wall -O0 
LFLAGS= -nostdlib -T BMA11_ls.ld -Wl,-Map=final.map
UF2=elf2uf2 final.elf final.uf2
DIS=arm-none-eabi-objdump -D final.elf > final.dis
BLOB=arm-none-eabi-objcopy -I binary -O elf32-littlearm -B arm --rename-section .data=.emudata emu_prog.prg emu_proga.o	
emu_proga.o:
	$(BLOB)	
final.elf:bs2_default_padded_checksummed.o vector_table_BMA10.o assembly.o emu_proga.o
	$(CC) $(LFLAGS) -o $@ $^
final.uf2: final.elf
	$(UF2) -o $@ $^
final.dis:final.elf
	$(DIS) 	
uf2: final.uf2 
dis: final.dis
prg: emu_proga.o 
link: final.elf
all:  bs2_default_padded_checksummed.o assembly.o vector_table_BMA10.o emu_proga.o
assembly.o:assembly.S
	$(CC) $(CFLAGS) -o $@ $^
bs2_default_padded_checksummed.o:bs2_default_padded_checksummed.S	
	$(CC) $(CFLAGS) -o $@ $^
vector_table_BMA10.o:vector_table_BMA10.S
	$(CC) $(CFLAGS) -o $@ $^
#"make full" compilies the arm program including the 6502 program using emu_prog.prg file
# first type "make ca65" and then type "make full"	
full:  uf2 dis

#********* makefile for cleaning RP204 and 6502 programs *******************
clean:
	-del -f $(wildcard *.o)  
	-del -f $(wildcard *.elf) 
	-del -f $(wildcard *.uf2)
	-del -f $(wildcard *.map)
	-del -f $(wildcard *.dis)
	-del -f $(wildcard *.prg)
	-del -f $(wildcard *.lst)
	
#********** makefile for compiling 6502 program using CA65 *****

CA65=ca65 -t none -l Pico_TIM.asm
LD65=ld65 --config ptim_ld65.cfg -o emu_prog.prg Pico_TIM.o -m Pico_TIM.m

ca65: emu_prog.prg
emu_prog.prg: Pico_TIM.o
	$(LD65)
Pico_TIM.o: Pico_TIM.asm
	$(CA65)