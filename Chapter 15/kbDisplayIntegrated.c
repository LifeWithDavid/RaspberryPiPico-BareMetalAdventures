/**
 * Combined KB and SSD1306 display for Binkenlights Computer
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdint.h>
#include "pico/stdlib.h"
#include "pico/binary_info.h"
#include "hardware/i2c.h"
#include "raspberry26x32.h"
#include "ssd1306_font.h"
#include "hardware/irq.h"
#include "hardware/clocks.h"
#include "hardware/pio.h"
#include "kb_scan_decode.pio.h"
#include "hardware/uart.h"

volatile uint mAR;		// Memory Address Register (32 bits)
volatile uint16_t kbReg = 0;	// Keyboard Register (16 bits)
volatile uint8_t kbControl; // keyboard control value (8 bits)
volatile uint8_t memData;	// Memory Data (8 bits)
static PIO PIO_O;       // pio object
static uint SM;         // pio state machine index
static uint PIO_IRQ;    // NVIC ARM CPU interrupt number
static int memOffset = 0x20020000; // location of the start of "6502" physical memory inside the Pico
volatile uint kbRow;    // Global data to pass kb row decimal value to main program
volatile uint kbCol;    // Global data to pass kb column decimal value to main program
volatile int *p_data;   // global pointer 
static uint keyDecode[4][6] = {{3,2,1,0,129,128},{7,6,5,4,131,130},{11,10,9,8,133,132},{15,14,13,12,135,134}};
 
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

void pioIRQ(){          //This is our callback function
   uint keyCode = pio_sm_get(PIO_O,SM); // This is the ISR shifted left (LSB last)  
   //pio_interrupt_clear(PIO_O, 0);
   kbControl = 0;
// This prints the keycode after the interrupt
   uint keyRowBit = keyCode & 0b1111; // isolates the key row 
   uint keyColBit = keyCode & 0b1111110000; // isolates the key column
   keyColBit = keyColBit >> 4; // shifts the key column 4 to the right to get rid of trailing zeros
   uint keyRow = convertBit2Dec(keyRowBit); //converts row bit position to decimal row number (start at 0)
   uint keyCol = convertBit2Dec(keyColBit); // converts column bit position to decimal column number (start at 0)
   uint16_t keyValue = decodeKeys(keyRow,keyCol); // this outputs a value based on the row and column
   if ((keyValue & (1<<7))==0) {
	   kbReg = kbReg << 4;
	   kbReg = kbReg + keyValue;
   }
	else {
		kbControl = (keyValue & 0b1111);
		switch (kbControl) {
			case 0:
				printf("function 0 \n");
				break;
			case 1:
				printf("function 1 \n");
				break;
			case 2:
				printf("function 2 \n");
				break;
			case 3:
				printf("function 3 \n");
				break;
			case 4:
				printf("function 4 \n");
				break;
			case 5:
				printf("Load MAR \n");
				mAR=kbReg + memOffset; // load the MAR with the keyboard register and align it with Pico physical memory
				printf("size of mAR: %d bytes\n", sizeof(mAR));
				printf("size of memData: %d bytes\n", sizeof(memData));
				memData = readOneByte(mAR);
				printf("MAR: %04x Data: %04x \n",mAR, memData);
				break;
			case 6:
				printf("Deposit %02x  \n", memData);
				memData = (kbReg & 0b11111111);
				printf("deposit 2 \n");
				printf("Data to store: %02x \n", memData);
				writeOneByte(mAR, memData);
				mAR = mAR +1;
				memData = readOneByte(mAR);
				break;
			case 7:
				printf("Examine \n");
				mAR = mAR +1;
				memData = readOneByte(mAR);
				printf("MAR: %04x Data: %04x \n",mAR, memData);
				break;
		}  
	}
	printf("KB Code: %010b KB Row: %1i  KB Column: %1i ASCII: %3i Ctrl: %3i KBR: %04x \n", keyCode, keyRow, keyCol, keyValue, kbControl, kbReg); 
	pio_interrupt_clear(PIO_O, 0);
}
void kbScanPio(uint pioNum) {
    PIO_O = pioNum ? pio1 : pio0; //Selects the pio instance (0 or 1 for pioNUM)
    PIO_IRQ = pioNum ? PIO1_IRQ_0 : PIO0_IRQ_0;  // Selects the NVIC PIO_IRQ to use		
    // Our assembled program needs to be loaded into this PIO's instruction
    // memory. This SDK function will find a location (offset) in the
    // instruction memory where there is enough space for our program. We need
    // to remember this location!
    uint offset = pio_add_program(PIO_O, &pio_kb_scan_irq_program); 
	uint ROW_START = 12; // the start of the row GPIOs (4 outputs)
	uint COL_START = 6;  // the start of the column GPIOs (6 inputs)
	
	// select the desired state machine clock frequency (2000 is about the lower limit)
	float SM_CLK_FREQ = 2000;

    // Find a free state machine on our chosen PIO (erroring if there are
    // none). Configure it to run our program, and start it, using the
    // helper function we included in our .pio file.
    SM = pio_claim_unused_sm(PIO_O, true);
    pio_kb_scan_irq_program_init(PIO_O, SM, offset, ROW_START, COL_START, SM_CLK_FREQ);	
	// this defines and enables the PIO IRQ handler
    // enable all PIO IRQs at the same time
	pio_set_irq0_source_mask_enabled(PIO_O, 3840, true); //setting all 4 at once
	irq_set_exclusive_handler(PIO_IRQ, pioIRQ);          //Set the handler in the NVIC
    irq_set_enabled(PIO_IRQ, true);                      //enabling the PIO1_IRQ_0
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
// Basic Bresenhams.
static void DrawLine(uint8_t *buf, int x0, int y0, int x1, int y1, bool on) {

    int dx =  abs(x1-x0);
    int sx = x0<x1 ? 1 : -1;
    int dy = -abs(y1-y0);
    int sy = y0<y1 ? 1 : -1;
    int err = dx+dy;
    int e2;

    while (true) {
        SetPixel(buf, x0, y0, on);
        if (x0 == x1 && y0 == y1)
            break;
        e2 = 2*err;

        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
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

int main() {
    stdio_init_all();
    sleep_ms(10000);  //gives me time to start PuTTY
	
#if !defined(i2c_default) || !defined(PICO_DEFAULT_I2C_SDA_PIN) || !defined(PICO_DEFAULT_I2C_SCL_PIN)
#warning i2c / SSD1306_i2d example requires a board with I2C pins
    puts("Default I2C pins were not defined");
#else
    // useful information for picotool
    bi_decl(bi_2pins_with_func(PICO_DEFAULT_I2C_SDA_PIN, PICO_DEFAULT_I2C_SCL_PIN, GPIO_FUNC_I2C));
    bi_decl(bi_program_description("SSD1306 OLED driver I2C front panel example for the Raspberry Pi Pico"));

    printf("Hello, SSD1306 OLED display and Keyboard \n");

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

    // intro sequence: flash the screen 3 times
    for (int i = 0; i < 3; i++) {
        SSD1306_send_cmd(SSD1306_SET_ALL_ON);    // Set all pixels on
        sleep_ms(500);
        SSD1306_send_cmd(SSD1306_SET_ENTIRE_ON); // go back to following RAM for pixel state
        sleep_ms(500);
    }
	
	uint16_t num = 60000;
	uint16_t num2 = 5000;
	char str[16];
	char kbString[16]; 
	float float_num = 3.14159;
	char float_str[16];
	int *p_data;
	// set up character array
	char *pc_disp = malloc(17);  //allocate 17 bytes for character array (16 for word and one for end byte)
	pc_disp[16] = '\0'; // assign end symbol to last byte
	uint16_t mask;  //set up mask for testing
	//uint16_t displayMAR;
	char lgt_on = '^'; //assign light on without separator
	char lgt_off = '_'; //assign light of without separator
	char lgt_on_sep = ']'; //assign light on with separator
	char lgt_off_sep = '['; //assign light off with separator
// The following 3 commands initialize the KB scanning PIO routines
    kbScanPio(0); // instantiates PIO 0
    uint msg = 0b10001000010001000010001000010001; //special sequencing word
    pio_sm_put(PIO_O, SM, msg); // this sends the special sequencing word	
restart:
	num = num + 1;
	mask = 0x8000;  //set up mask for testing
	// this steps through the register and converts to "lights" result is stored in pc_disp
	for(int i = 0; i <= 15; ++i) { // do it 16 times
		if((mask & num2) == 0) { // "and" the mask and number to check if byte is 0
			pc_disp[i] = lgt_off; // bit is 0 so turn light off
		}
		else {
			pc_disp[i] = lgt_on ;// otherwise turn the light on
		}
		mask = mask >> 1; // shift mask one bit to right and do it again
	}
	
	sprintf(float_str, "%f", float_num);
	sprintf(str, "MAR:%04X Data:%02X", (mAR & 0b1111111111111111),memData); //convert num to hex format (capitalized)
	sprintf(kbString, "KBR:%04X ", kbReg);
    char *text[] = {
        str,
        kbString,
        pc_disp,
        "A:      ^^_[__^_",
        "X:      __^]^^__",
        "Y:      ^_^]^_^_",
        "P:      _^/[_^_^",
        "                "
    };

    int y = 0;
    for (uint i = 0 ;i < count_of(text); i++) {
        //WriteString(buf, 5, y, text[i]);
		WriteString(buf, 0, y, text[i]);
        y+=8;
    }
	WriteSep(buf, 31, 16);
	WriteSep(buf, 63, 16);
	WriteSep(buf, 95, 16);
    render(buf, &frame_area);
    goto restart;
#endif
    return 0;
}
//**************************************************************
