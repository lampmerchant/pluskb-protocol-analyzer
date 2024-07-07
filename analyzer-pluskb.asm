;;; 80 characters wide please ;;;;;;;;;;;;;;;;;;;;;;;;;; 8-space tabs please ;;;


;
;;;
;;;;;  Macintosh Plus Serial Keyboard Protocol Analyzer
;;;
;


;;; Connections ;;;

;;;                                                              ;;;
;                    .--------.                                    ;
;            Supply -|01 \/ 08|- Ground                            ;
;          ---> RA5 -|02    07|- RA0 <--- Serial Keyboard Data     ;
;          ---> RA4 -|03    06|- RA1 <--- Serial Keyboard Clock    ;
;    !MCLR ---> RA3 -|04    05|- RA2 ---> UAT Tx                   ;
;                    '--------'                                    ;
;;;                                                              ;;;


;;; Assembler Directives ;;;

	list		P=PIC12F1501, F=INHX32, ST=OFF, MM=OFF, R=DEC, X=ON
	#include	P12F1501.inc
	errorlevel	-302	;Suppress "register not in bank 0" messages
	errorlevel	-224	;Suppress TRIS instruction not recommended msgs
	__config	_CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF
			;_FOSC_INTOSC	Internal oscillator, I/O on RA5
			;_WDTE_OFF	Watchdog timer disabled
			;_PWRTE_ON	Keep in reset for 64 ms on start
			;_MCLRE_ON	RA3/!MCLR is !MCLR
			;_CP_OFF	Code protection off
			;_BOREN_OFF	Brownout reset off
			;_CLKOUTEN_OFF	CLKOUT disabled, I/O on RA4
	__config	_CONFIG2, _WRT_OFF & _STVREN_ON & _BORV_LO & _LPBOR_OFF &_LVP_OFF
			;_WRT_OFF	Write protection off
			;_STVREN_ON	Stack over/underflow causes reset
			;_BORV_LO	Brownout reset voltage low trip point
			;_LPBOR_OFF	Low power brownout reset disabled
			;_LVP_OFF	High-voltage on Vpp to program


;;; Macros ;;;

DELAY	macro	value		;Delay 3*W cycles, set W to 0
	movlw	value
	decfsz	WREG,F
	bra	$-1
	endm

DNOP	macro
	bra	$+1
	endm


;;; Constants ;;;

;Pin Assignments:
SKC_PIN	equ	RA1	;Pin where serial keyboard clock is connected

;FLAGS:


;;; Variable Storage ;;;

	cblock	0x70	;Bank-common registers
	
	FLAGS	;You've got to have flags
	SK_FSAP	;Pointer to where to resume serial keyboard state machine
	SK_SR	;Serial keyboard shift register
	SK_STMR	;Serial keyboard startup timer
	TX_FSAP	;Pointer to where to resume UAT state machine
	TX_SR	;UAT shift register
	X9
	X8
	X7
	X6
	X5
	X4
	X3
	X2
	X1
	X0
	
	endc

	;Linear memory:
	;0x2000-0x201F - UAT queue (FSR1 = push pointer, FSR0 = pop pointer)


;;; Vectors ;;;

	org	0x0		;Reset vector
	goto	Init

	org	0x4		;Interrupt vector
	;fall through


;;; Interrupt Handler ;;;

Interrupt
	movlb	0		;Clear the NCO interrupt
	bcf	PIR2,NCO1IF	; "
	movf	TX_FSAP,W	;Resume the UAT state machine
	callw			; "
	movwf	TX_FSAP		;Save the address of next state
	retfie			;Done


;;; Hardware Initialization ;;;

Init
	banksel	OSCCON		;16 MHz high-freq internal oscillator
	movlw	B'01111000'
	movwf	OSCCON

	banksel	IOCAP		;Serial keyboard clock sets IOCAF on positive
	movlw	1 << SKC_PIN	; edges
	movwf	IOCAP

	banksel	OPTION_REG	;Timer0 ticks 1:256 with instruction clock, thus
	movlw	B'11010111'	; overflowing every 16.384 ms
	movwf	OPTION_REG

	banksel	NCO1CON		;NCO in pulse frequency mode with an increment
	movlw	0x1D		; value of 7550, resulting in clock pulses at a
	movwf	NCO1INCH	; rate of approximately 115200 Hz
	movlw	0x7E
	movwf	NCO1INCL
	movlw	B'10000001'
	movwf	NCO1CON

	banksel	CLC1CON		;CLC1 is a DFF which clocks in data from
	clrf	CLC1SEL0	; CLC1POL[1] on each tick of the NCO and outputs
	clrf	CLC1SEL1	; it on the UAT output (CLC1/RA2); CLC2 is a DFF
	movlw	B'00000010'	; which clocks in data from the serial keyboard
	movwf	CLC1POL		; data pin (CLC2IN1/RA0) on the rising edge of
	movlw	B'10000000'	; the serial keyboard clock pin (CLC2IN0/RA1)
	movwf	CLC1GLS0
	clrf	CLC1GLS1
	clrf	CLC1GLS2
	clrf	CLC1GLS3
	movlw	B'11000100'
	movwf	CLC1CON
	clrf	CLC2SEL0
	movlw	B'01010000'
	movwf	CLC2SEL1
	clrf	CLC2POL
	movlw	B'00000010'
	movwf	CLC2GLS0
	movlw	B'10000000'
	movwf	CLC2GLS1
	clrf	CLC2GLS2
	clrf	CLC2GLS3
	movlw	B'10000100'
	movwf	CLC2CON

	banksel	ANSELA		;All pins digital, not analog
	clrf	ANSELA

	banksel	TRISA		;Tx output, all other pins inputs
	movlw	B'00111011'
	movwf	TRISA

	banksel	PIE1
	movlw	1 << NCO1IE
	movwf	PIE2

	movlp	high SKFsaStart	;Initialize key globals
	movlw	0x20
	movwf	FSR0H
	movwf	FSR1H
	clrf	FSR0L
	clrf	FSR1L
	movlw	low SKFsaIgnore
	movwf	SK_FSAP
	movlw	61
	movwf	SK_STMR
	movlw	low TxFsaWait
	movwf	TX_FSAP

	movlw	B'11000000'	;Interrupt subsystem and peripheral interrupts
	movwf	INTCON		; (for NCO) on

	;fall through


;;; Mainline ;;;

Main
	movlb	7		;If an edge was detected on serial keyboard
	btfsc	IOCAF,SKC_PIN	; clock, deal with it
	call	SvcSK		; "
	btfsc	INTCON,TMR0IF	;If Timer0 overflowed, reset the serial keyboard
	call	SvcSKTimeout	; state machine
	bra	Main		;Loop

SvcSK
	bcf	IOCAF,SKC_PIN	;Clear the interrupt
	movf	SK_FSAP,W	;Resume the serial keyboard state machine
	callw			; "
	movwf	SK_FSAP		;Save the address of next state
	movlb	0		;Reset timeout Timer0 because we got a serial
	clrf	TMR0		; keyboard bit
	bcf	INTCON,TMR0IF	; "
	return			;Done

SvcSKTimeout
	movlb	0		;Reset Timer0 and its interrupt
	clrf	TMR0		; "
	bcf	INTCON,TMR0IF	; "
	movf	SK_STMR,W	;If the startup timer is not zero yet, ignore
	btfss	STATUS,Z	; the timeout for another cycle
	bra	SSKTim0		; "
	movlw	low SKFsaStart	;Reset the serial keyboard state machine
	movwf	SK_FSAP		; "
	return			;Done
SSKTim0	decf	SK_STMR,F	;Decrement the startup timer
	return			; "


;;; State Machines ;;;

	org	0x100

SKFsaIgnore
	retlw	low SKFsaIgnore	;Ignore noise from the keyboard on startup

SKFsaStart
	movlw	B'00000001'	;Clear serial keyboard shift register with just
	movwf	SK_SR		; sentinel bit
	;fall through

SKFsaBit
	movlb	30		;Rotate bit from DFF into shift register
	bcf	STATUS,C	; "
	btfsc	CLCDATA,1	; "
	bsf	STATUS,C	; "
	rlf	SK_SR,F		; "
	btfss	STATUS,C	;If a 0 fell out of the shift register, loop to
	retlw	low SKFsaBit	; wait for next bit
	movf	SK_SR,W		;If a 1 fell out of the shift register, the byte
	movwi	FSR1++		; is complete, push it onto the queue to send
	bcf	FSR1L,5		; "
	retlw	low SKFsaStart	;Transition to wait for the next byte to start

TxFsaWait
	movf	FSR0L,W		;If the queue is empty, wait until next bit time
	xorwf	FSR1L,W		; "
	btfsc	STATUS,Z	; "
	retlw	low TxFsaWait	; "
	moviw	FSR0++		;If the queue is not empty, pop the next byte
	bcf	FSR0L,5		; off, advance and wrap the pointer
	movwf	TX_SR		;Move it to the shift register
	movlb	30		;Set the DFF to output a start bit (0) next time
	bcf	CLC1POL,1	; "
	movlb	31		;Update FSR0L shadow register
	movf	FSR0L,W		; "
	movwf	FSR0L_SHAD	; "
	retlw	low TxFsaFirst	;Transition to send the first bit next time

TxFsaFirst
	bsf	STATUS,C	;Rotate a sentinel bit into the transmitter SR
	rrf	TX_SR,F		; and the first bit to send out
	bcf	STATUS,Z	;Clear the Z bit (so as to signal byte is not
	bra	TFBit0		; done) and rejoin code to send C below

TxFsaBit
	lsrf	TX_SR,F		;Shift the next bit to send out of the SR
TFBit0	movlb	30		;Copy the bit to send into the input of the DFF
	bcf	CLC1POL,1	; "
	btfsc	STATUS,C	; "
	bsf	CLC1POL,1	; "
	btfss	STATUS,Z	;If the SR is not yet zero, loop back to send
	retlw	low TxFsaBit	; the next bit next time; if it is, we just set
	retlw	low TxFsaWait	; up a stop bit, so loop to check for new data


;;; End of Program ;;;

	end
