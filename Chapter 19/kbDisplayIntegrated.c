/* 
#   BMA18-final: This is the emulator running on core 0 and the kbDisplayIntegrated running 
#   on core 1.  ASCII communications is by the Pico's USB port.  The emulator outputs 
#   through the kbDisplay program using two global variable, core0to1_flags, and core0to1_value 
#   and receives input through the intercore FIFO from kbDisplayIntegrated. 
#   Emulator status registers are stored in 5 variables in X scratch on every pass. The C program
#   retrieves those values as needed using structs.  The blinken lights display is expanded to 
#   include all registers.  Control functions are added.
   */
/* *
   * Combined KB and SSD1306 display for Binkenlights Computer
   * SPDX-License-Identifier: BSD-3-Clause
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdint.h>
#include "pico.h"
#include "pico/stdlib.h"
#include "pico/binary_info.h"
#include "pico/multicore.h"
#include "hardware/i2c.h"
#include "hardware/structs/sio.h"
#include "ssd1306_font.h"
#include "hardware/irq.h"
#include "hardware/clocks.h"
#include "hardware/pio.h"
#include "kb_scan_decode.pio.h"
#include "hardware/uart.h"

typedef struct __attribute__((packed)) {
    uint16_t prog_count;	//r3 16 lsb
	uint16_t r3_pad16;
    uint8_t acc_reg;		//r5 8 lsb
	uint16_t r5_pad16;
	uint8_t r5pad8;
    uint8_t flag_reg;		//r6 8 lsb
	uint16_t r6_pad16;
	uint8_t r6_pad8;
    uint8_t x_reg;			//r10 8 lsb
	uint16_t r10_pad16;
	uint8_t r10_pad8;
    uint8_t y_reg;			//r11 8 lsb
	uint16_t r11_pad16;
	uint8_t r11_pad8;
	uint16_t kbReg;			// keyboard register
	uint16_t kbReg_pad16;
} reg_block_t;

volatile uint mAR;		// Memory Address Register (32 bits)
volatile uint kbChanged = 1; //if set, some key has been pressed
volatile uint8_t kbControl; // keyboard control value (8 bits)
volatile uint8_t memData;	// Memory Data (8 bits)
static PIO PIO_O;       // pio object
static uint SM;         // pio state machine index
static uint PIO_IRQ;    // NVIC ARM CPU interrupt number
static int memOffset = 0x20020000; // location of the start of "6502" physical memory inside the Pico
volatile uint kbRow;    // Global data to pass kb row decimal value to main program
volatile uint kbCol;    // Global data to pass kb column decimal value to main program
volatile int *p_data;   // global pointer 
volatile uint resetStatus = 0; // global variable to convey status of the reset to "main_program()"
static uint keyDecode[4][6] = {{3,2,1,0,129,128},{7,6,5,4,131,130},{11,10,9,8,133,132},{15,14,13,12,135,134}};
extern volatile uint32_t pendingFunction;   // the pending functions from the assembly program
extern volatile uint32_t core0to1_flag;
extern volatile uint32_t core0to1_value;
extern reg_block_t __regs_base__;   // same symbol as in linker
#define regs ((volatile reg_block_t *)&__regs_base__)
__attribute__((noreturn)) void main_program(void);

//**********kb scan routines*************

uint decodeKeys(uint row, uint col)  {   //This takes the row and column and returns an ASCII Character
	char keyChar = (char)keyDecode[row][col];
	return keyChar;
	}
	
uint convertBit2Dec(uint bitwiseData) { //Converts the bit position number to decimal (bit 0=0, ie. 0b0010->0d1)
	int decimalData;
	for (decimalData = 0; decimalData < 6; ++decimalData) { 
		if ((bitwiseData & (1 << decimalData)) != 0 ) // keep shifting 1 to the left until it finds the set bit position
			break;  //Set bit found, quit the loop
		else;		// Set bit not found, move 1 over an additionsl space and check again
	}
	return decimalData;  // return the bit position decimal number
} 
uint8_t readOneByte (uint memAdd) { //This reads one byte from the memory location "memAdd"
		uint8_t readData;
		asm volatile("ldrb %0, [%1]"	"\n\t"
					: "=r" (readData)
					: "r" (memAdd)
					);
		return readData;
		}
	
void writeOneByte (uint memAdd, uint8_t writeData) { //This writes one byte (writeData) to the memory location "memAdd"
		asm volatile("strb %1, [%0]"	"\n\t"
					: // no outputs
					: "r" (memAdd) , "r" (writeData)
					);
		}	
		
void pioIRQ(){          //This is our PIO callback function

   uint keyCode = pio_sm_get(PIO_O,SM); // This is the ISR shifted left (LSB last)  
   kbControl = 0;
   kbChanged = 1;  //sets kbChanged because a key was pressed
// This generates the keycode after the interrupt
   uint keyRowBit = keyCode & 0b1111; // isolates the key row 
   uint keyColBit = keyCode & 0b1111110000; // isolates the key column
   keyColBit = keyColBit >> 4; // shifts the key column 4 to the right to get rid of trailing zeros
   uint keyRow = convertBit2Dec(keyRowBit); //converts row bit position to decimal row number (start at 0)
   uint keyCol = convertBit2Dec(keyColBit); // converts column bit position to decimal column number (start at 0)
   uint16_t keyValue = decodeKeys(keyRow,keyCol); // this outputs a value based on the row and column
   pio_interrupt_clear(PIO_O, 0);
   if ((keyValue & (1<<7))==0) {   // if bit 7 of the keyValue is cleared, then the key is a data key (0-f)
	   regs->kbReg = regs->kbReg << 4;          // update the keyboard register; shift left 1 nibble 
	   regs->kbReg = regs->kbReg + keyValue;    // and add the new nibble
   }
	else {                        // bit 7 of keyValue is set, so the key is a control key
		kbControl = ((keyValue & 0b1111)+1); // 1 is added to the keyboard function so that function 0 does not = 0
		// this allows for easy testing if there is a pending function i.e. if pendingFunction ==0 then no function pending
		switch (kbControl) {
			case 1: //run/halt
				if (pendingFunction == 0) {
					multicore_fifo_push_blocking(0x80000001); // this pushes the control key code to the emulator
				}
				else {
					multicore_fifo_push_blocking(0x80000000);
				}
				break;
			case 2:  //reset
			
				multicore_fifo_push_blocking(0x80000002);
				resetStatus = 1;
				break;
			case 3:		// single step

				multicore_fifo_push_blocking(0x80000003);
				break;
			case 4:		// IRQ

				multicore_fifo_push_blocking(0x80000004);
				break;
			case 5:		// START

				multicore_fifo_push_blocking(0x80000005);
				break;
			case 6: // moves the keyboard register into the memory address register
				mAR=regs->kbReg + memOffset; // load the MAR with the keyboard register and align it with Pico physical memory
				memData = readOneByte(mAR);
				break;
			case 7:  // this deposits the lower byte in the keyboard register into memory and increments the MAR
				memData = (regs->kbReg & 0b11111111); // 
				writeOneByte(mAR, memData);
				mAR = mAR +1;
				memData = readOneByte(mAR);
				break;
			case 8: // this examines the byte pointed to by the MAR, then increments the MAR
				mAR = mAR +1;
				memData = readOneByte(mAR);
				break;
		}  
	}
}

void convert_to_lights(uint16_t num2, char lgt_on, char lgt_off, int str_len, char *out) {
	uint16_t mask = 1;
    mask <<= str_len-1;
    for (int i = 0; i < str_len; ++i) {
        out[i] = (num2 & mask) ? lgt_on : lgt_off;
        mask >>= 1;
    }
    out[str_len] = '\0';
}		
void kbScanPio(uint pioNum) {

    // Select PIO instance (0 or 1)
    PIO_O = pioNum ? pio1 : pio0;

    // Select NVIC IRQ variable for later use with exclusive handler
    PIO_IRQ = pioNum ? PIO1_IRQ_0 : PIO0_IRQ_0;

    // Load assembled program into PIO instruction memory
    uint offset = pio_add_program(PIO_O, &pio_kb_scan_irq_program);

    uint ROW_START = 12; // first row GPIO
    uint COL_START = 6;  // first column GPIO

    float SM_CLK_FREQ = 2000; // desired SM clock frequency

    // Claim a free state machine
    SM = pio_claim_unused_sm(PIO_O, true);

    // Initialize the program
    pio_kb_scan_irq_program_init(PIO_O, SM, offset, ROW_START, COL_START, SM_CLK_FREQ);

    // Enable all 4 IRQ sources at once
    pio_set_irq0_source_mask_enabled(PIO_O, 3840, true);

    // Set the handler and enable it — works with variable
    irq_set_exclusive_handler(PIO_IRQ, pioIRQ);
    irq_set_enabled(PIO_IRQ, true);
}

//***********ssd1306 routines************
/* 
// This code should be eventually located at 0x20010000
// Graphics memory starts at 0x20030000
// This code explores converting a number from memory and turning it into "lights" 3/6/25
// Define the size of the display we have attached. This can vary, make sure you
// have the right size defined or the output will look rather odd!
// Code has been tested on 128x32 and 128x64 OLED displays
*/
#define SSD1306_HEIGHT              64
#define SSD1306_WIDTH               128
#define SSD1306_I2C_ADDR            _u(0x3C)

// 400 is usual, but often these can be overclocked to improve display response.
// Tested at 1000 on both 32 and 84 pixel height devices and it worked.
#define SSD1306_I2C_CLK             400
//#define SSD1306_I2C_CLK             1000
// commands (see datasheet)
#define SSD1306_SET_MEM_MODE        _u(0x20)
#define SSD1306_SET_COL_ADDR        _u(0x21)
#define SSD1306_SET_PAGE_ADDR       _u(0x22)
#define SSD1306_SET_HORIZ_SCROLL    _u(0x26)
#define SSD1306_SET_SCROLL          _u(0x2E)
#define SSD1306_SET_DISP_START_LINE _u(0x40)
#define SSD1306_SET_CONTRAST        _u(0x81)
#define SSD1306_SET_CHARGE_PUMP     _u(0x8D)
#define SSD1306_SET_SEG_REMAP       _u(0xA0)
#define SSD1306_SET_ENTIRE_ON       _u(0xA4)
#define SSD1306_SET_ALL_ON          _u(0xA5)
#define SSD1306_SET_NORM_DISP       _u(0xA6)
#define SSD1306_SET_INV_DISP        _u(0xA7)
#define SSD1306_SET_MUX_RATIO       _u(0xA8)
#define SSD1306_SET_DISP            _u(0xAE)
#define SSD1306_SET_COM_OUT_DIR     _u(0xC0)
#define SSD1306_SET_COM_OUT_DIR_FLIP _u(0xC0)
#define SSD1306_SET_DISP_OFFSET     _u(0xD3)
#define SSD1306_SET_DISP_CLK_DIV    _u(0xD5)
#define SSD1306_SET_PRECHARGE       _u(0xD9)
#define SSD1306_SET_COM_PIN_CFG     _u(0xDA)
#define SSD1306_SET_VCOM_DESEL      _u(0xDB)
#define SSD1306_PAGE_HEIGHT         _u(8)
#define SSD1306_NUM_PAGES           (SSD1306_HEIGHT / SSD1306_PAGE_HEIGHT)
#define SSD1306_BUF_LEN             (SSD1306_NUM_PAGES * SSD1306_WIDTH)
#define SSD1306_WRITE_MODE         _u(0xFE)
#define SSD1306_READ_MODE          _u(0xFF)

struct render_area {
    uint8_t start_col;
    uint8_t end_col;
    uint8_t start_page;
    uint8_t end_page;
    int buflen;
    };

void calc_render_area_buflen(struct render_area *area) {
    // calculate how long the flattened buffer will be for a render area
    //area->buflen = (area->end_col - area->start_col + 1) * (area->end_page - area->start_page + 1);
	area->buflen = (area->end_col - area->start_col + 1) * (area->end_page - area->start_page + 1);//see if we can start writing at column 0 2/26
}

#ifdef i2c_default

void SSD1306_send_cmd(uint8_t cmd) {
    // I2C write process expects a control byte followed by data
    // this "data" can be a command or data to follow up a command
    // Co = 1, D/C = 0 => the driver expects a command
    uint8_t buf[2] = {0x80, cmd};
    i2c_write_blocking(i2c_default, SSD1306_I2C_ADDR, buf, 2, false);
}

void SSD1306_send_cmd_list(uint8_t *buf, int num) {
    for (int i=0;i<num;i++)
        SSD1306_send_cmd(buf[i]);
}

void SSD1306_send_buf(uint8_t buf[], int buflen) {
    // in horizontal addressing mode, the column address pointer auto-increments
    // and then wraps around to the next page, so we can send the entire frame
    // buffer in one gooooooo!
    // copy our frame buffer into a new buffer because we need to add the control byte
    // to the beginning

    uint8_t *temp_buf = malloc(buflen + 1);

    temp_buf[0] = 0x40;
    memcpy(temp_buf+1, buf, buflen);

    i2c_write_blocking(i2c_default, SSD1306_I2C_ADDR, temp_buf, buflen + 1, false);

    free(temp_buf);
}

void SSD1306_init() {
    // Some of these commands are not strictly necessary as the reset
    // process defaults to some of these but they are shown here
    // to demonstrate what the initialization sequence looks like
    // Some configuration values are recommended by the board manufacturer

    uint8_t cmds[] = {
        SSD1306_SET_DISP,               // set display off
        /* memory mapping */
        SSD1306_SET_MEM_MODE,           // set memory address mode 0 = horizontal, 1 = vertical, 2 = page
        0x00,                           // horizontal addressing mode
        /* resolution and layout */
        SSD1306_SET_DISP_START_LINE,    // set display start line to 0
        SSD1306_SET_SEG_REMAP | 0x01,   // set segment re-map, column address 127 is mapped to SEG0
        SSD1306_SET_MUX_RATIO,          // set multiplex ratio
        SSD1306_HEIGHT - 1,             // Display height - 1
        SSD1306_SET_COM_OUT_DIR | 0x08, // set COM (common) output scan direction. Scan from bottom up, COM[N-1] to COM0
        SSD1306_SET_DISP_OFFSET,        // set display offset
        0x00,                           // no offset
        SSD1306_SET_COM_PIN_CFG,        // set COM (common) pins hardware configuration. Board specific magic number.
                                        // 0x02 Works for 128x32, 0x12 Possibly works for 128x64. Other options 0x22, 0x32
#if ((SSD1306_WIDTH == 128) && (SSD1306_HEIGHT == 32))
        0x02,
#elif ((SSD1306_WIDTH == 128) && (SSD1306_HEIGHT == 64))
        0x12,
#else
        0x02,
#endif
        /* timing and driving scheme */
        SSD1306_SET_DISP_CLK_DIV,       // set display clock divide ratio
        0x80,                           // div ratio of 1, standard freq
        SSD1306_SET_PRECHARGE,          // set pre-charge period
        0xF1,                           // Vcc internally generated on our board
        SSD1306_SET_VCOM_DESEL,         // set VCOMH deselect level
        0x30,                           // 0.83xVcc
        /* display */
        SSD1306_SET_CONTRAST,           // set contrast control
        0xFF,
        SSD1306_SET_ENTIRE_ON,          // set entire display on to follow RAM content
        SSD1306_SET_NORM_DISP,           // set normal (not inverted) display
        SSD1306_SET_CHARGE_PUMP,        // set charge pump
        0x14,                           // Vcc internally generated on our board
        SSD1306_SET_SCROLL | 0x00,      // deactivate horizontal scrolling if set. This is necessary as memory writes will corrupt if scrolling was enabled
        SSD1306_SET_DISP | 0x01, // turn display on
    };

    SSD1306_send_cmd_list(cmds, count_of(cmds));
}

void SSD1306_scroll(bool on) {
    // configure horizontal scrolling
    uint8_t cmds[] = {
        SSD1306_SET_HORIZ_SCROLL | 0x00,
        0x00, // dummy byte
        0x00, // start page 0
        0x00, // time interval
        0x03, // end page 3 SSD1306_NUM_PAGES ??
        0x00, // dummy byte
        0xFF, // dummy byte
        SSD1306_SET_SCROLL | (on ? 0x01 : 0) // Start/stop scrolling
    };

    SSD1306_send_cmd_list(cmds, count_of(cmds));
}

void render(uint8_t *buf, struct render_area *area) {
    // update a portion of the display with a render area
    uint8_t cmds[] = {
        SSD1306_SET_COL_ADDR,
        area->start_col,
        area->end_col,
        SSD1306_SET_PAGE_ADDR,
        area->start_page,
        area->end_page
    };

    SSD1306_send_cmd_list(cmds, count_of(cmds));
    SSD1306_send_buf(buf, area->buflen);
}

static void SetPixel(uint8_t *buf, int x,int y, bool on) {
    assert(x >= 0 && x < SSD1306_WIDTH && y >=0 && y < SSD1306_HEIGHT);

    // The calculation to determine the correct bit to set depends on which address
    // mode we are in. This code assumes horizontal

    // The video ram on the SSD1306 is split up in to 8 rows, one bit per pixel.
    // Each row is 128 long by 8 pixels high, each byte vertically arranged, so byte 0 is x=0, y=0->7,
    // byte 1 is x = 1, y=0->7 etc

    // This code could be optimised, but is like this for clarity. The compiler
    // should do a half decent job optimising it anyway.

    const int BytesPerRow = SSD1306_WIDTH ; // x pixels, 1bpp, but each row is 8 pixel high, so (x / 8) * 8

    int byte_idx = (y / 8) * BytesPerRow + x;
    uint8_t byte = buf[byte_idx];

    if (on)
        byte |=  1 << (y % 8);
    else
        byte &= ~(1 << (y % 8));

    buf[byte_idx] = byte;
}

static inline int GetFontIndex(uint8_t ch) {
    if (ch >= '0' && ch <='_') {
        return  ch - '0' + 1;
    }
 //   else if (ch >= '0' && ch <='@') {
 //       return  ch - '0' + 27;
 //   }
    else return  0; // Not got that char so space.
}

static void WriteChar(uint8_t *buf, int16_t x, int16_t y, uint8_t ch) {
    if (x > SSD1306_WIDTH - 8 || y > SSD1306_HEIGHT - 8)
        return;

    // For the moment, only write on Y row boundaries (every 8 vertical pixels)
    y = y/8;

    ch = toupper(ch); //converts ASCII to upper case
    int idx = GetFontIndex(ch);// gets the index number the character in ssd1306_font.h
    int fb_idx = y * 128 + x;

    for (int i=0;i<8;i++) {
        buf[fb_idx++] = font[idx * 8 + i];
    }
}

static void WriteString(uint8_t *buf, int16_t x, int16_t y, char *str) {
    // Cull out any string off the screen
	// x = start column, y = start row
    if (x > SSD1306_WIDTH - 8 || y > SSD1306_HEIGHT - 8)
        return;

    while (*str) {
        WriteChar(buf, x, y, *str++);
        x+=8;
    }
}

static void WriteSep(uint8_t *buf, int16_t x, int16_t y) { //writes a vertical line at the specified location
    if (x > SSD1306_WIDTH - 8 || y > SSD1306_HEIGHT - 8)
        return;
    // For the moment, only write on Y row boundaries (every 8 vertical pixels)
    y = y/8;

    int fb_idx = y * 128 + x;
    buf[fb_idx] = 0xff;
    }
#endif
// *****************************************************************
__attribute__((noreturn))
void main_program(void) {
	if (resetStatus != 0) goto after_reset;   // has the emulator just been reset, if so skip forward
    stdio_init_all();
	uint32_t sp;
	__asm volatile ("mov %0, sp" : "=r" (sp));

	multicore_fifo_drain();
	multicore_fifo_clear_irq();
	core0to1_flag = 0;
	core0to1_value = 0;
	int ch = 0;
 	printf(" Welcome to 'Blinken', a 6502 inspired cyber-platform featuring a front panel. ");
	#if !defined(i2c_default) || !defined(PICO_DEFAULT_I2C_SDA_PIN) || !defined(PICO_DEFAULT_I2C_SCL_PIN)
	#warning i2c / SSD1306_i2d example requires a board with I2C pins
		puts("Default I2C pins were not defined");
	#else
    // useful information for picotool
    bi_decl(bi_2pins_with_func(PICO_DEFAULT_I2C_SDA_PIN, PICO_DEFAULT_I2C_SCL_PIN, GPIO_FUNC_I2C));
    bi_decl(bi_program_description("SSD1306 OLED driver I2C front panel example for the Raspberry Pi Pico"));

    // I2C is "open drain", pull ups to keep signal high when no data is being
    // sent
    i2c_init(i2c_default, SSD1306_I2C_CLK * 1000);
    gpio_set_function(PICO_DEFAULT_I2C_SDA_PIN, GPIO_FUNC_I2C);
    gpio_set_function(PICO_DEFAULT_I2C_SCL_PIN, GPIO_FUNC_I2C);
    gpio_pull_up(PICO_DEFAULT_I2C_SDA_PIN);
    gpio_pull_up(PICO_DEFAULT_I2C_SCL_PIN);

    // run through the complete initialization process
    SSD1306_init();

    // Initialize render area for entire frame (SSD1306_WIDTH pixels by SSD1306_NUM_PAGES pages)
    struct render_area frame_area = {
        start_col: 0,
        end_col : SSD1306_WIDTH - 1,
        start_page : 0,
        end_page : SSD1306_NUM_PAGES - 1
        };

    calc_render_area_buflen(&frame_area);

    // zero the entire display
    uint8_t buf[SSD1306_BUF_LEN];
    memset(buf, 0, SSD1306_BUF_LEN);
    render(buf, &frame_area);
	// The following 3 commands initialize the KB scanning PIO routines
    kbScanPio(0); // instantiates PIO 0
    uint msg = 0b10001000010001000010001000010001; //special sequencing word
    pio_sm_put(PIO_O, SM, msg); // this sends the special sequencing word

after_reset: // *************************************after reset*****************
	sleep_ms(100);
	resetStatus = 0;				// clears the reset status flag
	pendingFunction = 0;
	kbChanged = 1;
	core0to1_flag = 0;   // initializes the core 0 to core 1 transfer memory locations
	core0to1_value = 0;
	regs->kbReg = 0;		// initialize the keyboard register
	mAR=regs->kbReg + memOffset; // initialize the mAR to the start of emu memory
	char str[16];        // set up chr array for top line of display
	char kbString[16];   // set up chr array for second line of display
	int *p_data;
	// set up character array
	char *pc_disp = malloc(17);  //allocate 17 bytes for character array (16 for word and one for end byte)														
	char *a_disp = malloc(9);  //allocate 9 bytes for character array (8 for word and one for end byte)
	char acc_string[17];
	char *x_disp = malloc(9);  //allocate 9 bytes for character array (8 for word and one for end byte)
	char x_string[17];
	char *y_disp = malloc(9);  //allocate 9 bytes for character array (8 for word and one for end byte)
	char y_string[17];
	char *p_disp = malloc(9);  //allocate 9 bytes for character array (8 for word and one for end byte)
	char p_string[17];
	char run[] =" RUN";
	char halt[] = "HALT";
	
restart:  // this is the main scanning loop

	if (resetStatus != 0) goto after_reset;  // if reset ha been pushed, then restart the emulator
	convert_to_lights(regs->prog_count, '^', '_', 16, pc_disp); // convert the registers to blinking lights
	convert_to_lights(regs->acc_reg, '^', '_', 8, a_disp);      // '^' is light on & '_' is light off
	convert_to_lights(regs->x_reg, '^', '_', 8, x_disp);        // '8' is length of register in bits 
	convert_to_lights(regs->y_reg, '^', '_', 8, y_disp);
	convert_to_lights(regs->flag_reg, '^', '_', 8, p_disp);
	
	if (kbChanged !=0) {
		sprintf(str, "MAR:%04X Data:%02X", (mAR & 0b1111111111111111),memData); //convert num to hex format (capitalized)
		sprintf(kbString, "KBR:%04X    %s\n", regs->kbReg, (pendingFunction) ? halt : run);
	}
	kbChanged = 0;
	sprintf(acc_string, "A:      %s\n", a_disp); // add text and formatting to the 8 bit blinken lights lines
	sprintf(x_string, "X:      %s\n", x_disp);
	sprintf(y_string, "Y:      %s\n", y_disp);
	sprintf(p_string, "P:      %s\n", p_disp);
    char *text[] = {    // build the entire text array for the ssd1306 display
		str,
        kbString,
        pc_disp,
        acc_string,
        x_string,
        y_string,
        p_string,
    };

	int y = 0;
    for (uint i = 0 ;i < count_of(text); i++) {  // send the text array to the ssd1306 display
		WriteString(buf, 0, y, text[i]);
        y+=8;
    }
	WriteSep(buf, 31, 16);   // add the "nibble" separators to the blinken lights display
	WriteSep(buf, 63, 16);
	WriteSep(buf, 95, 16);
	WriteSep(buf, 95, 24);
	WriteSep(buf, 95, 32);
	WriteSep(buf, 95, 40);
	WriteSep(buf, 95, 48);
    render(buf, &frame_area);

	while (core0to1_flag != 0) { // if the flag is not 0, then ascii data from the emulator is available 
		uint32_t received_data = core0to1_value; // Pop the ascii data
		core0to1_flag = 0; // resets the flag, data register is now empty
		printf("%c", received_data);	// send the emulator ascii data to the standard I/O	
		ch = getchar_timeout_us(1000);  // check for character from std I/O (terminal)
		if (ch != PICO_ERROR_TIMEOUT) { // 1 ms is added to improve throughput of ascii data from emulator
			multicore_fifo_push_blocking(ch);
		}
	}
	ch = getchar_timeout_us(0);  
	if (ch != PICO_ERROR_TIMEOUT) {
			multicore_fifo_push_blocking(ch);
	}	
	goto restart;

#endif

}

//**************************************************************
