/* Life with David BMA11 - linker script - emulator
   Bootloader 2 goes to FLASH at 0x10000000, vector table at 0x10000100, 
   memcopy at 0x10000200, "reset" at 0x20000000
*/

MEMORY
{
    FLASH(rx) : ORIGIN = 0x10000000, LENGTH = 2048k
    RAM(rwx) : ORIGIN =  0x20000000, LENGTH = 128k
	EMU_RAM(rwx) : ORIGIN = 0x20020000, LENGTH = 128k
    SCRATCH_X(rwx) : ORIGIN = 0x20040000, LENGTH = 4k
    SCRATCH_Y(rwx) : ORIGIN = 0x20041000, LENGTH = 4k
}

 ENTRY(__entry_point__)


SECTIONS
{
 /* Second stage bootloader is prepended to the image. It must be 256 bytes big
       and checksummed. It is usually built by the boot_stage2 target
       in the Raspberry Pi Pico SDK
    */

    .flash_begin : {
        __flash_binary_start__ = .;
    } > FLASH

    .boot2 : {
        __entry_point__ = .;
		__boot2_start__ = .;
        KEEP (*(.boot2))
        __boot2_end__ = .;
    } > FLASH

    ASSERT(__boot2_end__ - __boot2_start__ == 256,
        "ERROR: Pico second stage bootloader must be 256 bytes in size")

    /* The second stage will always enter the image at the start of .text.
       The debugger will use the ELF entry point, which is the _entry_point
       symbol if present, otherwise defaults to start of .text.
       This can be used to transfer control back to the bootrom on debugger
       launches only, to perform proper flash setup.
    */

    .text : {
        __logical_binary_start__ = .;
        KEEP (*(.vectors))
		
        KEEP (*(.binary_info_header))
        __binary_info_header_end__ = .;
		. = __logical_binary_start__ + 0x100;
	
		__reset_start__ = .;
		KEEP (*(.reset*))
		__reset_end__ = .;
	} >  FLASH

	
	.dummy : {
		__main_load_start__ = .;
	} > FLASH	
	
    .main : {
		. = ALIGN(4);
		__ram_start__ = .;
		__main_start__ = .;
		KEEP (*(.inst_lookup*))
		. = ALIGN(4);
		__lookup_start__ = .;
		KEEP (*(.emu_vector*))
		KEEP (*(.inst_exec*))		
		KEEP (*(.comms*))
		KEEP (*(.int_handler*))
		__main_end__ = .;
	} > RAM AT> FLASH
		
	.rodata : {
        . = ALIGN(4);
        *(.rodata*)
        . = ALIGN(4);
        *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.flashdata*)))
        . = ALIGN(4);
		__rodata_end__ = .;
    } > RAM AT> FLASH
	
	.ram_vector_table (COPY): {
        *(.ram_vector_table)
    } > RAM

    .data : {
        __data_start__ = .;
		
		 *(.data*)
		 . = ALIGN(4);
        __data_end__ = .;
    } > RAM AT> FLASH

	.emudummy : {
		__emu_load_start__ = .;
	} > FLASH	
	
	.emudata : {
		__emu_ram_start__ = .;
		__emu_start__ = .;
		KEEP (*(.emudata*))
		__emu_end__ = .;
	} > EMU_RAM AT> FLASH	
	
    .bss  : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.bss*)))
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > RAM
	
    .heap (COPY):
    {
        __end__ = .;
        end = __end__;
        *(.heap*)
        __HeapLimit__ = .;
    } > RAM
}