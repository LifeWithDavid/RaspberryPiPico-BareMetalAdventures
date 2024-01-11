; da65 V2.13.3 - (C) Copyright 2000-2009,  Ullrich von Bassewitz
; Created    2017-03-12 231527
; Input file TIM_DUMP_1.prg
; Page       1
		.include "Pico_TIM_ehbasic.asm"
        .setcpu "6502"
		.feature labels_without_colons
		.segment "CODE"                 ; Switch to CODE2 segment
        
        
		.org $D000
; ----------------------------------------------------------------------------
L00EC           = $00EC
UINT   			= $FFF8


; ----------------------------------------------------------------------------
		MP0	=	$D000
		MP1	=	$D100
		MP2	=	$D200
		MP3	=	$D300


NMINT  	sta     $F9     		; save A                        		; 7000 85 F9
        lda     #$23            ; SET A=# TO INDICATE NMINT ENTRY       ; 7002 A9 23
        bne     B3              ; JMP B3             					; 7004 D0 55
;		
RESET  	lda     #$16            ; INIT DIR REG, PCR IC 1 RELOCATES		; 7006 A9 16
        jmp     RESET1          ; ***********This is a patch for the new TIM
																		; 7008 8D 03 6E                 
        ldx     #$08            ; X=0									; 700B A2 08
L700D  	lda     INTVEC-1,x      ; INITALIZE INT VECTORS					; 700D BD F7 73                 
        sta     $FFF7,x         ; 7010 9D F7 FF                 
        dex                     ; 7013 CA                       
		bne		L700D			;**above code left in place to keep I/O routines in the same place
		
		;******** New TIM patch - UART initialization 
RESET1	jsr		UINIT
		jmp		ENDINIT
UINIT	lda		#$80			; set DLAB
		sta		$E803			;save to Line control reg.
		lda		#$1A			;UART baud divisor $DO - 300, $1A - 2400 baud
		sta		$E800
		lda		#$00			;MSB of baud divisor
		sta		$E801
		LDA		#$07			;Clear DLAB, set word & parity, 8-N-2
		sta		$E803			;end of UART setting routine
		

		rts						;A spot to add an RTS if neccessary
		lda		#$4C			;put in jump to $D000
		sta		$5000			;This code left here to keep I/O locations the same
		lda		#$00			;This code originally added a jump for $fff9 since there 
		sta		$5001			;there was a bad bit 7 in the TIM chip
		lda		#$D0
		sta		$5002
		rts
		
		;**************end of patch
ENDINIT							;Finish up init
		cli						;Enable INTS
		brk						;Enter TIM by BRK
INTRQ	sta     $F9             ; SAVE ACC								; 7052 85 F9
        pla                     ; FLAGS TO A							; 7054 68     
        pha                     ; RESTORE STACK STATUS					; 7055 48   
        and     #$10            ; TEST BRK FLAG							; 7056 29 10 
        beq     BX              ; USER INTERRUPT						; 7058 F0 27
        asl     a               ; SET A=SPACE (10 X 2 = 2C)				; 705A 0A 
B3  	sta     $FE             ; SAVE INT TYPE FLAG					; 705B 85 FE 
        cld                                     ; 705D D8    
        lsr     a                               ; 705E 4A   
        stx     $FA                             ; 705F 86 FA 
        sty     $FB                             ; 7061 84 FB
        pla                                     ; 7063 68   
        sta     $F8                             ; 7064 85 F8
        pla                                     ; 7066 68
        adc     #$FF                            ; 7067 69 FF
        sta     $F6                             ; 7069 85 F6
        pla                                     ; 706B 68   
        adc     #$FF                            ; 706C 69 FF
        sta     $F7                             ; 706E 85 F7
        tsx                                     ; 7070 BA  
        stx     $FC                             ; 7071 86 FC
        jsr     CRLF                           ; 7073 20 8A 72
        ldx     $FE                             ; 7076 A6 FE 
        lda     #$2A                            ; 7078 A9 2A    
        jsr     WRTWO                           ; 707A 20 C0 72 
        lda     #$52                            ; 707D A9 52    
        bne     S0                           ; 707F D0 16 
BX  	lda     $F9                             ; 7081 A5 F9    
        jmp     (UINT)                         ; 7083 6C F8 FF 
; ----------------------------------------------------------------------------
START  	lda     #$00                            ; 7086 A9 00
        sta     $E7                             ; 7088 85 E7
        sta     $E4                             ; 708A 85 E4
        jsr     CRLF                           ; 708C 20 8A 72
        lda     #$2E                            ; 708F A9 2E
        jsr     WRT                           ; 7091 20 C6 72 
        jsr     RDT                           ; 7094 20 E9 72
S0  	ldx     #$06                            ; 7097 A2 06   
S1  	cmp     CMDS,x                         ; 7099 DD 06 71 
        bne     S2                           ; 709C D0 19 
        lda     $FD                             ; 709E A5 FD 
        sta     $E9                             ; 70A0 85 E9  
        stx     $FD                             ; 70A2 86 FD
        lda     #MP1/256						; 70A4 A9 71
        sta     $ED                             ; 70A6 85 ED
        lda     ADRS,x                         ; 70A8 BD 0D 71
        sta     L00EC                           ; 70AB 85 EC
        cpx     #$03                            ; 70AD E0 03
        bcs     IJMP                           ; 70AF B0 03
        jsr     SPAC2                           ; 70B1 20 74 73
IJMP  	jmp     (L00EC)                         ; 70B4 6C EC 00
; ----------------------------------------------------------------------------
S2  	dex                                     ; 70B7 CA 
        bpl     S1                           ; 70B8 10 DF
ERROPR 	lda     #$3F                            ; 70BA A9 3F .?
        jsr     WRT                           ; 70BC 20 C6 72
        bcc     START                           ; 70BF 90 C5
DCMP  	sec                                     ; 70C1 38 
        lda     $F0                             ; 70C2 A5 F0
        sbc     $EE                             ; 70C4 E5 EE
        sta     $E5                             ; 70C6 85 E5
        lda     $F1                             ; 70C8 A5 F1
        sbc     $EF                             ; 70CA E5 EF
        tay                                     ; 70CC A8   
        ora     $E5                             ; 70CD 05 E5
        rts                                     ; 70CF 60 
; ----------------------------------------------------------------------------
PUTP  	lda     $EE                             ; 70D0 A5 EE
        sta     $F6                             ; 70D2 85 F6
        lda     $EF                             ; 70D4 A5 EF
        sta     $F7                             ; 70D6 85 F7
        rts                                     ; 70D8 60   
; ----------------------------------------------------------------------------
ZTMP  	lda     #$00                            ; 70D9 A9 00 
        sta     $EE,x                           ; 70DB 95 EE
        sta     $EF,x                           ; 70DD 95 EF
        rts                                     ; 70DF 60
; ----------------------------------------------------------------------------
BYTF  	jsr     RDOB                           ; 70E0 20 B3 73
        bcc     BY3                           ; 70E3 90 10 
        ldx     #$00                            ; 70E5 A2 00
        sta     ($EE,x)                         ; 70E7 81 EE
        cmp     ($EE,x)                         ; 70E9 C1 EE
        beq     BY2                           ; 70EB F0 05 
        pla                                     ; 70ED 68 
        pla                                     ; 70EE 68 
        jmp     ERROPR                           ; 70EF 4C BA 70 
; ----------------------------------------------------------------------------
BY2  	jsr     DADD                           ; 70F2 20 7C 72
BY3  	jsr     INCTMP                           ; 70F5 20 97 73
        dec     $FE                             ; 70F8 C6 FE
        rts                                     ; 70FA 60
; ----------------------------------------------------------------------------
SETR  	lda     #$F8                            ; 70FB A9 F8
        sta     $EE                             ; 70FD 85 EE
        lda     #$00                            ; 70FF A9 00
        sta     $EF                             ; 7101 85 EF
        lda     #$05                            ; 7103 A9 05
        rts                                     ; 7105 60 
		NOP			;brute force method of moving command table to 
		NOP			;to next page so command indexing works right
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		NOP
		
; ----------------------------------------------------------------------------
CMDS  	.byte   ':'                             ; 7106 3A   
        .byte   'R'                             ; 7107 52   R
        .byte   'M'                           	; 7108      M
		.byte   'G'								;		  	G
		.byte   'H'								;			H	
        .byte   'L'                             ; 710B 4C   L
        .byte   'W'                             ; 710C 57   W
ADRS  	.byte   ALTER-MP1                       ; 710D 3A   
        .byte   DSPLYR-MP1                      ; 710E 14                       .
        .byte   DSPLYM-MP1                             ; 710F 1C                       .
        .byte   GO-MP1                            ; 7110 5C                       
		.byte 	HSP-MP1                             ; 7111 6F                       o
        .byte   LH-MP1                          ; 7112 74                       t
        .byte   WO-MP1                            ; 7113 C2                       .
DSPLYR 	jsr     WRPC                           ; 7114 20 A6 72                  .r
        jsr     SETR                           ; 7117 20 FB 70                  .p
        bne     M0                           ; 711A D0 07                    ..
DSPLYM 	jsr     RD0A                           ; 711C 20 A4 73                  .s
        bcc     ERRS1                           ; 711F 90 16                    ..
        lda     #$08                            ; 7121 A9 08                    ..
M0  	sta     $FE                             ; 7123 85 FE                    ..
        ldy     #$00                            ; 7125 A0 00                    ..
M1  	jsr     SPACE                           ; 7127 20 77 73                  ws
        lda     ($EE),y                         ; 712A B1 EE                    ..
        jsr     WROB                           ; 712C 20 B1 72                  .r
        iny                                     ; 712F C8                       .
        dec     $FE                             ; 7130 C6 FE                    ..
        bne     M1                           ; 7132 D0 F3                    ..
BEQS1  	jmp     START                           ; 7134 4C 86 70                 L.p
; ----------------------------------------------------------------------------
ERRS1  	jmp     ERROPR                           ; 7137 4C BA 70                 L.p
; ----------------------------------------------------------------------------
ALTER  	dec     $E9                             ; 713A C6 E9                    ..
        bne     A3                           ; 713C D0 0D                    ..
        jsr     RD0A                           ; 713E 20 A4 73                  .s
        bcc     A2                           ; 7141 90 03                    ..
        jsr     PUTP                           ; 7143 20 D0 70                  .p
A2  	jsr     SETR                           ; 7146 20 FB 70                  .p
        bne     A4                           ; 7149 D0 05                    ..
A3  	jsr     WROA                           ; 714B 20 9A 72                  .r
        lda     #$08                            ; 714E A9 08                    ..
A4  	sta     $FE                             ; 7150 85 FE                    ..
A5  	jsr     SPACE                           ; 7152 20 77 73                  ws
        jsr     BYTF                           ; 7155 20 E0 70                  .p
        bne     A5                           ; 7158 D0 F8                    ..
        beq     BEQS1                           ; 715A F0 D8                    ..
GO     	ldx     $FC                             ; 715C A6 FC                    ..
        txs                                     ; 715E 9A                       .
        lda     $F7                             ; 715F A5 F7                    ..
        pha                                     ; 7161 48                       H
        lda     $F6                             ; 7162 A5 F6                    ..
        pha                                     ; 7164 48                       H
        lda     $F8                             ; 7165 A5 F8                    ..
        pha                                     ; 7167 48                       H
        lda     $F9                             ; 7168 A5 F9                    ..
        ldx     $FA                             ; 716A A6 FA                    ..
        ldy     $FB                             ; 716C A4 FB                    ..
        rti                                     ; 716E 40                       @
; ----------------------------------------------------------------------------
HSP     inc     $E8                             ; 716F E6 E8                    ..
        jmp     START                           ; 7171 4C 86 70                 L.p
; ----------------------------------------------------------------------------
LH     	jsr     RDT                           ; 7174 20 E9 72                  .r
        jsr     CRLF                           ; 7177 20 8A 72                  .r
        ldx     $E8                             ; 717A A6 E8                    ..
        stx     $E7                             ; 717C 86 E7                    ..
LH1  	jsr     RDT                           ; 717E 20 E9 72                  .r
        cmp     #$3B                            ; 7181 C9 3B                    .;
        bne     LH1                           ; 7183 D0 F9                    ..
        ldx     #$04                            ; 7185 A2 04                    ..
        jsr     ZTMP                           ; 7187 20 D9 70                  .p
        jsr     RDOB                           ; 718A 20 B3 73                  .s
        bne     LH2                           ; 718D D0 06                    ..
        ldx     #$00                            ; 718F A2 00                    ..
        stx     $E7                             ; 7191 86 E7                    ..
        beq     BEQS1                           ; 7193 F0 9F                    ..
LH2  	sta     $FE                             ; 7195 85 FE                    ..
        jsr     DADD                           ; 7197 20 7C 72                  |r
        jsr     RDOB                           ; 719A 20 B3 73                  .s
        sta     $EF                             ; 719D 85 EF                    ..
        jsr     DADD                           ; 719F 20 7C 72                  |r
        jsr     RDOB                           ; 71A2 20 B3 73                  .s
        sta     $EE                             ; 71A5 85 EE                    ..
        jsr     DADD                           ; 71A7 20 7C 72                  |r
LH3  	jsr     BYTF                           ; 71AA 20 E0 70                  .p
        bne     LH3                           ; 71AD D0 FB                    ..
        jsr     RD0A                           ; 71AF 20 A4 73                  .s
        lda     $F2                             ; 71B2 A5 F2                    ..
        sta     $F0                             ; 71B4 85 F0                    ..
        lda     $F3                             ; 71B6 A5 F3                    ..
        sta     $F1                             ; 71B8 85 F1                    ..
        jsr     DCMP                           ; 71BA 20 C1 70                  .p
        beq     LH1                           ; 71BD F0 BF                    ..
ERRP1	jmp     ERROPR                           ; 71BF 4C BA 70                 L.p
; ----------------------------------------------------------------------------
WO     	jsr     RDT                           ; 71C2 20 E9 72                  .r
        sta     $FE                             ; 71C5 85 FE                    ..
        jsr     SPACE                           ; 71C7 20 77 73                  ws
        jsr     RD0A                           ; 71CA 20 A4 73                  .s
        jsr     T2T2                           ; 71CD 20 87 73                  .s
        jsr     SPACE                           ; 71D0 20 77 73                  ws
        jsr     RD0A                           ; 71D3 20 A4 73                  .s
        jsr     T2T2                           ; 71D6 20 87 73                  .s
        jsr     RDT                           ; 71D9 20 E9 72                  .r
        lda     $FE                             ; 71DC A5 FE                    ..
        cmp     #$48                            ; 71DE C9 48                    .H
        bne     WB                           ; 71E0 D0 59                    .Y
WH0  	ldx     $E4                             ; 71E2 A6 E4                    ..
        bne     BCCST                           ; 71E4 D0 52                    .R
        jsr     CRLF                           ; 71E6 20 8A 72                  .r
        ldx     #$18                            ; 71E9 A2 18                    ..
        stx     $FE                             ; 71EB 86 FE                    ..
        ldx     #$04                            ; 71ED A2 04                    ..
        jsr     ZTMP                           ; 71EF 20 D9 70                  .p
        lda     #$3B                            ; 71F2 A9 3B                    .;
        jsr     WRT                           ; 71F4 20 C6 72                  .r
        jsr     DCMP                           ; 71F7 20 C1 70                  .p
        tya                                     ; 71FA 98                       .
        bne     WH1                           ; 71FB D0 0A                    ..
        lda     $E5                             ; 71FD A5 E5                    ..
        cmp     #$17                            ; 71FF C9 17                    ..
        bcs     WH1                           ; 7201 B0 04                    ..
        sta     $FE                             ; 7203 85 FE                    ..
        inc     $FE                             ; 7205 E6 FE                    ..
WH1  	lda     $FE                             ; 7207 A5 FE                    ..
        jsr     DADD                           ; 7209 20 7C 72                  |r
        jsr     WROB                           ; 720C 20 B1 72                  .r
        lda     $EF                             ; 720F A5 EF                    ..
        jsr     DADD                           ; 7211 20 7C 72                  |r
        jsr     WROB                           ; 7214 20 B1 72                  .r
        lda     $EE                             ; 7217 A5 EE                    ..
        jsr     DADD                           ; 7219 20 7C 72                  |r
        jsr     WROB                           ; 721C 20 B1 72                  .r
WH2  	ldy     #$00                            ; 721F A0 00                    ..
        lda     ($EE),y                         ; 7221 B1 EE                    ..
        jsr     DADD                           ; 7223 20 7C 72                  |r
        jsr     WROB                           ; 7226 20 B1 72                  .r
        jsr     INCTMP                           ; 7229 20 97 73                  .s
        dec     $FE                             ; 722C C6 FE                    ..
        bne     WH2                           ; 722E D0 EF                    ..
        jsr     WROA4                           ; 7230 20 9E 72                  .r
        jsr     DCMP                           ; 7233 20 C1 70                  .p
        bcs     WH0                           ; 7236 B0 AA                    ..
BCCST  	jmp     START                           ; 7238 4C 86 70                 L.p
; ----------------------------------------------------------------------------
WB  	inc     $FD                             ; 723B E6 FD                    ..
WB1  	lda     $E4                             ; 723D A5 E4                    ..
        bne     BCCST                           ; 723F D0 F7                    ..
        lda     #$04                            ; 7241 A9 04                    ..
        sta     L00EC                           ; 7243 85 EC                    ..
        jsr     CRLF                           ; 7245 20 8A 72                  .r
        jsr     WROA                           ; 7248 20 9A 72                  .r
WBNPF  	jsr     SPACE                           ; 724B 20 77 73                  ws
        ldx     #$09                            ; 724E A2 09                    ..
        stx     $FE                             ; 7250 86 FE                    ..
        lda     ($E5,x)                         ; 7252 A1 E5                    ..
        sta     $FF                             ; 7254 85 FF                    ..
        lda     #$42                            ; 7256 A9 42                    .B
        bne     WBF2                           ; 7258 D0 08                    ..
WBF1  	lda     #$50                            ; 725A A9 50                    .P
        asl     $FF                             ; 725C 06 FF                    ..
        bcs     WBF2                           ; 725E B0 02                    ..
        lda     #$4E                            ; 7260 A9 4E                    .N
WBF2  	jsr     WRT                           ; 7262 20 C6 72                  .r
        dec     $FE                             ; 7265 C6 FE                    ..
        bne     WBF1                           ; 7267 D0 F1                    ..
        lda     #$46                            ; 7269 A9 46                    .F
        jsr     WRT                           ; 726B 20 C6 72                  .r
        jsr     INCTMP                           ; 726E 20 97 73                  .s
        dec     L00EC                           ; 7271 C6 EC                    ..
        bne     WBNPF                           ; 7273 D0 D6                    ..
        jsr     DCMP                           ; 7275 20 C1 70                  .p
        bcs     WB1                           ; 7278 B0 C3                    ..
        bcc     BCCST                           ; 727A 90 BC                    ..
DADD  	pha                                     ; 727C 48                       H
        clc                                     ; 727D 18                       .
        adc     $F2                             ; 727E 65 F2                    e.
        sta     $F2                             ; 7280 85 F2                    ..
        lda     $F3                             ; 7282 A5 F3                    ..
        adc     #$00                            ; 7284 69 00                    i.
        sta     $F3                             ; 7286 85 F3                    ..
        pla                                     ; 7288 68                       h
        rts                                     ; 7289 60                       `
; ----------------------------------------------------------------------------
CRLF  	ldx     #$0D                            ; 728A A2 0D                    ..
        lda     #$0A                            ; 728C A9 0A                    ..
        jsr     WRTWO                           ; 728E 20 C0 72                  .r
        ldx     $E3                             ; 7291 A6 E3                    ..
CR1		NOP										; Originally a delay  7293 20 1D 73
		NOP										; but not needed now
		NOP
        dex                                     ; 7296 CA                       .
        bne     CR1                           ; 7297 D0 FA                    ..
        rts                                     ; 7299 60                       `
; ----------------------------------------------------------------------------
WROA  	ldx     #$01                            ; 729A A2 01                    ..
        bne     WROA1                           ; 729C D0 0A                    ..
WROA4  	ldx     #$05                            ; 729E A2 05                    ..
        bne     WROA1                           ; 72A0 D0 06                    ..
WROA6	ldx     #$07                            ; 72A2 A2 07                    ..
        bne     WROA1                           ; 72A4 D0 02                    ..
WRPC  	ldx     #$09                            ; 72A6 A2 09                    ..
WROA1  	lda     $ED,x                           ; 72A8 B5 ED                    ..
        pha                                     ; 72AA 48                       H
        lda     $EE,x                           ; 72AB B5 EE                    ..
        jsr     WROB                           ; 72AD 20 B1 72                  .r
        pla                                     ; 72B0 68                       h
WROB  	pha                                     ; 72B1 48                       H
        lsr     a                               ; 72B2 4A                       J
        lsr     a                               ; 72B3 4A                       J
        lsr     a                               ; 72B4 4A                       J
        lsr     a                               ; 72B5 4A                       J
        jsr     ASCII                           ; 72B6 20 58 73                  Xs
        tax                                     ; 72B9 AA                       .
        pla                                     ; 72BA 68                       h
        and     #$0F                            ; 72BB 29 0F                    ).
        jsr     ASCII                           ; 72BD 20 58 73                  Xs
WRTWO  	pha                                     ; 72C0 48                       H
        txa                                     ; 72C1 8A                       .
        jsr     WRT                           ; 72C2 20 C6 72                  .r
        pla                                     ; 72C5 68                       h
		;Output serial data - use a UART instead of TIM
		
		
		;Write a Character to UART 
		;For TIM, acc and X are cleared
WRT  	jsr WUART								;Call UART write
		lda	#$00								;Clear acc (required by TIM)
		ldx	#$00								;Clear x (required by TIM)
		rts

;This is the start of the write character that is used by ehbasic
;Character in acc., acc. & control reg preserved
WUART	pha										;Push acc & control reg to stack
		php	

; following code removed, will never have THRE cleared at this point; so don't need to check		
;LWLOOP	lda		#$20							;strip out "THRE" (bit 5)
;		bit		$E805
;		beq		LWLOOP							;if THRE = 0 then THRE is still full
;		plp										;restore control reg.
;		pla										;restore acc.
		sta		$E801							;write character
		lda		$E805							; load status register							
		and		#$DF							; clear bit 5 (THRE Transmit Holding Register Empty)
		sta		$E805							; store the line control register again (bit 1 for read, bit 5 for write)
		plp
		pla
		rts						
		
		nop										;bruteforce method of aligning the TIM read routine for legacy programs;
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
; ----------------------------------------------------------------------------
;TIM read entry,
;waits until character is available and then returns character in acc.
; For TIM, x is cleared, character in acc.

RDT											
		jsr	LRLOOP								;call the read subroutine
		bcc	RDT								;if carry is cleared, do it again
		jsr	WUART								;echo read character
		ldx #$00								;Clear x reg (required by TIM)		
		rts										;Character is in acc. and return

;-----------------------------------------------------------------------------		
;Read a character from UART used by ehbasic
;carry flag cleared if character is not available,
;carry flag set and character in acc. if character is available		

LRLOOP	lda	#$01								;load mask of $01, set means there is data to receive		
		bit	$E805								;compare with UART control reg.
		bne	LGTCHR								;character is available so skip 1st return
CCLEAR	clc
		bcc LRRET								;character not available or LF so return with carry cleared
LGTCHR 	lda $E805								; load line control register
		and #$FE								; clear bit 0, cleared means receive data fifo empty
		sta $E805								; store UART line control register
		lda	$E800								;read character
		cmp #$0A								;is it a line feed?
		beq	CCLEAR								;if so; return with carry cleared
		sec										;set carry to signal valid character
LRRET	rts

    
; ----------------------------------------------------------------------------
RDHSR  	lda     $6E02                           ; 733D AD 02 6E                 ..n
        and     #$08                            ; 7340 29 08                    ).
        beq     RDHSR                           ; 7342 F0 F9                    ..
        ldx     $6E00                           ; 7344 AE 00 6E                 ..n
        lda     $6E02                           ; 7347 AD 02 6E                 ..n
        ora     #$04                            ; 734A 09 04                    ..
        sta     $6E02                           ; 734C 8D 02 6E                 ..n
        and     #$FB                            ; 734F 29 FB                    ).
        sta     $6E02                           ; 7351 8D 02 6E                 ..n
        txa                                     ; 7354 8A                       .
        and     #$7F                            ; 7355 29 7F                    ).
        rts                                     ; 7357 60                       `
; ----------------------------------------------------------------------------
ASCII  	clc                                     ; 7358 18                       .
        adc     #$06                            ; 7359 69 06                    i.
        adc     #$F0                            ; 735B 69 F0                    i.
        bcc     ASC1                           ; 735D 90 02                    ..
        adc     #$06                            ; 735F 69 06                    i.
ASC1  	adc     #$3A                            ; 7361 69 3A                    i
        pha                                     ; 7363 48                       H
        cmp     #$42                            ; 7364 C9 42                    .B
        bne     ASCX                           ; 7366 D0 0A                    ..
        lda     $FD                             ; 7368 A5 FD                    ..
        cmp     #$07                            ; 736A C9 07                    ..
        bne     ASCX                           ; 736C D0 04                    ..
        pla                                     ; 736E 68                       h
        lda     #$20                            ; 736F A9 20                    . 
        pha                                     ; 7371 48                       H
ASCX  	pla                                     ; 7372 68                       h
        rts                                     ; 7373 60                       `
; ----------------------------------------------------------------------------
SPAC2  	jsr     SPACE                           ; 7374 20 77 73                  ws
SPACE  	pha                                     ; 7377 48                       H
        txa                                     ; 7378 8A                       .
        pha                                     ; 7379 48                       H
        tya                                     ; 737A 98                       .
        pha                                     ; 737B 48                       H
        lda     #$20                            ; 737C A9 20                    . 
        jsr     WRT                           ; 737E 20 C6 72                  .r
        pla                                     ; 7381 68                       h
        tay                                     ; 7382 A8                       .
        pla                                     ; 7383 68                       h
        tax                                     ; 7384 AA                       .
        pla                                     ; 7385 68                       h
        rts                                     ; 7386 60                       `
; ----------------------------------------------------------------------------
T2T2  	ldx     #$02                            ; 7387 A2 02                    ..
T2T21  	lda     $ED,x                           ; 7389 B5 ED                    ..
        pha                                     ; 738B 48                       H
        lda     $EF,x                           ; 738C B5 EF                    ..
        sta     $ED,x                           ; 738E 95 ED                    ..
        pla                                     ; 7390 68                       h
        sta     $EF,x                           ; 7391 95 EF                    ..
        dex                                     ; 7393 CA                       .
        bne     T2T21                           ; 7394 D0 F3                    ..
        rts                                     ; 7396 60                       `
; ----------------------------------------------------------------------------
INCTMP 	inc     $EE                             ; 7397 E6 EE                    ..
        beq     INCT1                           ; 7399 F0 01                    ..
        rts                                     ; 739B 60                       `
; ----------------------------------------------------------------------------
INCT1  	inc     $EF                             ; 739C E6 EF                    ..
        beq     SETWRP                           ; 739E F0 01                    ..
        rts                                     ; 73A0 60                       `
; ----------------------------------------------------------------------------
SETWRP 	inc     $E4                             ; 73A1 E6 E4                    ..
        rts                                     ; 73A3 60                       `
; ----------------------------------------------------------------------------
RD0A  	jsr     RDOB                           ; 73A4 20 B3 73                  .s
        bcc     RD0A2                           ; 73A7 90 02                    ..
        sta     $EF                             ; 73A9 85 EF                    ..
RD0A2  	jsr     RDOB                           ; 73AB 20 B3 73                  .s
        bcc     RDEXIT                           ; 73AE 90 02                    ..
        sta     $EE                             ; 73B0 85 EE                    ..
RDEXIT 	rts                                     ; 73B2 60                       `
; ----------------------------------------------------------------------------
RDOB  	tya                                     ; 73B3 98                       .
        pha                                     ; 73B4 48                       H
        lda     #$00                            ; 73B5 A9 00                    ..
        sta     L00EC                           ; 73B7 85 EC                    ..
        jsr     RDT                           ; 73B9 20 E9 72                  .r
        cmp     #$0D                            ; 73BC C9 0D                    ..
        bne     RDOB1                           ; 73BE D0 06                    ..
        pla                                     ; 73C0 68                       h
        pla                                     ; 73C1 68                       h
        pla                                     ; 73C2 68                       h
        jmp     START                           ; 73C3 4C 86 70                 L.p
; ----------------------------------------------------------------------------
RDOB1  	cmp     #$20                            ; 73C6 C9 20                    . 
        bne     RDOB2                           ; 73C8 D0 0A                    ..
        jsr     RDT                           ; 73CA 20 E9 72                  .r
        cmp     #$20                            ; 73CD C9 20                    . 
        bne     RDOB3                           ; 73CF D0 0F                    ..
        clc                                     ; 73D1 18                       .
        bcc     RDOB4                           ; 73D2 90 12                    ..
RDOB2  	jsr     HEXIT                           ; 73D4 20 EB 73                  .s
        asl     a                               ; 73D7 0A                       .
        asl     a                               ; 73D8 0A                       .
        asl     a                               ; 73D9 0A                       .
        asl     a                               ; 73DA 0A                       .
        sta     L00EC                           ; 73DB 85 EC                    ..
        jsr     RDT                           ; 73DD 20 E9 72                  .r
RDOB3  	jsr     HEXIT                           ; 73E0 20 EB 73                  .s
        ora     L00EC                           ; 73E3 05 EC                    ..
        sec                                     ; 73E5 38                       8
RDOB4  	tax                                     ; 73E6 AA                       .
        pla                                     ; 73E7 68                       h
        tay                                     ; 73E8 A8                       .
        txa                                     ; 73E9 8A                       .
        rts                                     ; 73EA 60

; ----------------------------------------------------------------------------
HEXIT  	cmp     #$3A                            ; 73EB C9 3A                    .
        php                                     ; 73ED 08                       .
        and     #$0F                            ; 73EE 29 0F                    ).
        plp                                     ; 73F0 28                       (
        bcc     HEXC9                           ; 73F1 90 02                    ..
        adc     #$08                            ; 73F3 69 08                    i.
HEXC9  	rts                                     ; 73F5 60                       `
; ----------------------------------------------------------------------------

		.segment "VECTORS" 
		.org $FFF8
INTVEC	
		.addr	NMINT							; 73F8 00 70                    
		.addr	NMINT							; 73FA 00 70                    
		.addr	RESET							; 73FC 06 70                    
		.addr	INTRQ							; 73FE 52 70  

.end		
 
