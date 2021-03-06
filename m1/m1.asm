	include "neogeo.inc"
	include "../common/error_codes.inc"
	include "../common/comm.inc"
	include "m1.inc"
	include "macros.inc"

	org 	$0000

	jp	_start

	rorg	RST_PSUB_ENTER, $ff
	jp	psub_enter


	rorg	RST_PSUB_EXIT, $ff
	jp	psub_exit


	rorg	RST_HANDLE_Z80_ERROR_CODE, $ff
	jp	handle_z80_error_code


	rorg	RST_PSUB_YM2610_WRITE_PORT0, $ff
	ld	hl, ym2610_write_port0_psub
	jp	psub_enter


; interrupts from ym2610
	rorg	RST_IRQ, $ff
	ex	af, af'
	cp	YM2610_IRQ_EXPECTED
	jr	z, .expected_interrupt
	cp	YM2610_IRQ_UNEXPECTED
	jr	z, .unexpected_interrupt

	; a' is in an unknown state, which implies we are not in our irq test
	; functions.  This shouldn't happen if the _start function was run,
	; since one of the first things it does is disable interrupts.  The
	; likely cause of this was a failed slot switch where we never got
	; the NMI reset command (0x03).
	;
	; It seems like there are 2 possibilities that can cause this:
	; 1. The sm1 had interrupts enabled and the ym2610 just triggered one.
	; 2. When the slot switch happened the PC was at a rom location that
	;    has our fill byte (0xff), which is instruction rst #$38 causing
	;    a jump to our irq code.
	;
	; Our best course of action in either case is to run the _start function
	; and attempt to recover.
	jp	_start


.unexpected_interrupt:
	ld	a, EC_YM2610_IRQ_UNEXPECTED
	jp	handle_z80_error_code

.expected_interrupt:
	ex	af, af'
	ld	l, $ff
	reti


; NMIs from 68k
	rorg	RST_NMI, $ff
	nop
	nop
	nop
	nop
	in	a,($00)
	out	($00),a
	out	($0c),a
	jp	_start


; z80 errors play 6 bits/tones
handle_z80_error_code:
	ld	b, $06
	jr	handle_error_code

; 68k errors play 7 bits/tones
handle_68k_error_code:
	ld	b, $07
	jr	handle_error_code

; params:
;  a = error code
;  b = number of bits to play
handle_error_code:
	di			; disable ints
	out	($18), a	; disable nmi

	ld	c, a
	or	$40		; flag to indicate z80 error
	out	($00), a
	out	($0c), a	; send the error code to 68k


	ld	a, $08
	sub	b

.loop_bitshift			; shift over so bit 8 is the
	sla	c		; start of the error code
	dec	a
	jr	nz, .loop_bitshift

.loop_next_bit:
	sla	c
	ld	a, $02		; bit is 0
	jr	nc, .play_sound
	ld	a, $01		; bit is 1

.play_sound:
	exx
	ld	c, $01		; course tune register (cha)
	ld	b, a
	PSUB	ym2610_write_port0

	ld	bc, $0000	; fine tune register (cha)
	PSUB_YMWP0

	ld	bc, $0f08	; volume (cha)
	PSUB_YMWP0

	ld	bc, $fe07	; enable tone A? (cha)
	PSUB_YMWP0

	ld	bc, $c000	; 319488us / 319ms
	PSUB	delay

	ld	bc, $ff07	; disable tone A? (cha)
	PSUB_YMWP0

	ld	bc, $4000	; 106496us / 106ms
	PSUB	delay

	exx
	djnz 	.loop_next_bit

.loop_wait_68k_input
	in	a, ($00)
	or	a
	jr	z, .loop_wait_68k_input

	cpl
	out	($0c), a

.loop_stall
	jr	.loop_stall


ym2610_make_noise_psub:
	ld	b, $04

.loop_again:
	exx
	ld	bc, $0001		; course tune (cha)
	PSUB_YMWP0

	ld	bc, $8000		; fine tune (cha)
	PSUB_YMWP0

	ld	bc, $0f08		; volume (cha)
	PSUB_YMWP0

	ld	bc, $fe07		; tone enable? (cha)
	PSUB_YMWP0

	ld	bc, $1000		; 26624us / 26ms
	PSUB	delay

	ld	bc, $ff07		; tone disable? (cha)
	PSUB_YMWP0

	ld	bc, $1000		; 26624us / 26ms
	PSUB	delay

	exx
	djnz .loop_again
	PSUB_RETURN


; params:
;  bc * 6.5us = how long to delay
delay_psub:
	dec	bc			; 6 cycles
	ld	a, c			; 4 cycles
	or	b			; 4 cycles
	jr	nz, delay_psub		; 12 cycles
	PSUB_RETURN

; params:
;  de, d = data to write, e = ym2610 register
ym2610_write_port0:
	ld	a, e
	out	(YM2610_PORT0_REGISTER), a

	ld	b, $ff
.loop_busy_register_load:
	in	a, (YM2610_PORT0_REGISTER)	; bit 8 will be 1 while ym is busy loading register
	rlca
	jr	nc, .register_loaded
	djnz	.loop_busy_register_load
	jr	.busy_timeout

.register_loaded:
	ld	a, d
	out	(YM2610_PORT0_DATA), a

	ld	b, $ff
.loop_busy_data_load:
	in	a, (YM2610_PORT0_REGISTER)
	rlca
	jr	nc, .register_data_loaded
	djnz	.loop_busy_data_load

.busy_timeout:
	or	$ff
	ret

.register_data_loaded:
	ret

; params:
;  de, d = data to write, e = ym2610 register
; never called
ym2610_write_port1:
	ld	a, e
	out	(YM2610_PORT1_REGISTER), a
.loop_busy_register_load:
	in	a, (YM2610_PORT0_REGISTER)	; bit 8 will be 1 while ym is busy loading register
	rlca
	jr	c, .loop_busy_register_load

	ld	a, d
	out	(YM2610_PORT1_DATA), a

.loop_busy_data_load:
	in	a, (YM2610_PORT0_REGISTER)
	rlca
	jr	c, .loop_busy_data_load
	ret

; params:
;  bc, b = data to write, c = ym2610 register
; assuming its doing the delay instead of the polling
; like the non-psub version because there could be
; a connectivity issue between the z80/ym2610 and
; we dont want to get stuck waiting for not-busy
ym2610_write_port0_psub:
	ld	a, c
	out	(YM2610_PORT0_REGISTER), a
	add	hl, hl			; delay a bit before next write to ym
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	a, b
	out	(YM2610_PORT0_DATA), a
	PSUB_RETURN

; params:
;  bc, b = data to write, c = ym2610 register
; never called
ym2610_write_port1_psub:
	ld	a, c
	out	(YM2610_PORT1_REGISTER), a
	add	hl, hl			; delay a bit before next write to ym
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	a, b
	out	(YM2610_PORT1_DATA), a
	PSUB_RETURN

_start:
	di
	im	1
	out	($18), a

	PSUB	ym2610_make_noise

	PSUB	rom_mirror_test
	jr	z, .test_passed_rom_mirror
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_rom_mirror:
	PSUB	rom_crc32_test
	jr	z, .test_passed_rom_crc32
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_rom_crc32:
	PSUB	ram_oe_test
	jr	z, .test_passed_ram_oe
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ram_oe:
	PSUB	ram_we_test
	jr	z, .test_passed_ram_we
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ram_we:
	PSUB	ram_data_tests
	jr	z, .test_passed_ram_data
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ram_data:
	PSUB	ram_address_tests
	jr	z, .test_passed_ram_address
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ram_address:
	PSUB	ym2610_io_tests
	jr	z, .test_passed_ym2610_io
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ym2610_io:
	PSUB	m68k_comm_test
	jr	z, .test_passed_m68k_comm_test
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_m68k_comm_test:
	jp	run_subroutine_tests


psub_enter:
	ld	a, r
	add	a, $80
	ld	r, a
	jp	p, .nested_call
	ld	ix, $0000
	add	ix, de
	jp	(hl)

.nested_call:
	ld	iy, $0000
	add	iy, de
	jp	(hl)

psub_exit:
	ex	af, af'
	ld	a, r		; dont clobber a while we figure out what register
	add	a, $80		; to jp back to
	ld	r, a
	jp	m, .nested_return
	ex	af, af'
	jp	(ix)

.nested_return:
	ex	af, af'
	jp	(iy)

; This source gets compiled to a size of 2048 ($0800) and
; is mirror'ed 15 times to make up the first 32k of the
; m1 rom.  At $07fb of each mirror contains a byte that
; represents the mirror number.  The running copy is
; 0, first mirror is 1, 2nd mirror is 2, etc.  The below
; function makes sure these mirror numbers match up. If
; they dont it points to there being a problem with
; one or more of the address lines between the z80 and
; m1 rom
rom_mirror_test_psub:
	ld	hl, ROM_MIRROR_OFFSET
	ld	de, $800		; size of each mirror
	ld	a, $00
	ld	b, $10

.loop_next_mirror:
	cp	(hl)
	jr	nz, .test_failed_abort
	inc	a
	add	hl, de
	djnz	.loop_next_mirror

	xor	a
	PSUB_RETURN

.test_failed_abort:
	ld	a, EC_Z80_M1_UPPER_ADDRESS
	or	a
	PSUB_RETURN


rom_crc32_test_psub:
	ld	bc, $0000
	exx
	ld	bc, ROM_CRC32_OFFSET
	exx
	PSUB	calc_crc32

	cp	a
	ld	hl, (ROM_CRC32_OFFSET)
	sbc	hl, bc
	jr	nz, .test_failed

	ld	hl, (ROM_CRC32_OFFSET + 2)
	sbc	hl, de
	jr	nz, .test_failed

	xor	a
	PSUB_RETURN

.test_failed:
	ld	a, EC_Z80_M1_CRC
	or	a
	PSUB_RETURN

sm1_tests:
	; copy the sm1 related test code into ram
	ld	de, Z80_RAM_START
	ld	hl, SM1_TEST_CODE_START
	ld	bc, SM1_TEST_CODE_END - SM1_TEST_CODE_START
	ldir

	; change the PSUB_RETURN at the end of calc_crc32_psub to a ret ($c9) instruction
	; so we can use it as a normal function instead of a psub.
	ld	hl, Z80_RAM_START + (sm1_crc32_test - SM1_TEST_CODE_START) - 1
	ld	(hl), $c9

	jp	Z80_RAM_START

SM1_TEST_CODE_START:
	; request bios switch to sm1 rom
	ld	a, COMM_SM1_TEST_SWITCH_SM1
	out	($00), a
	out	($0c), a

	ld	bc, $3000
.loop_wait_switch_sm1:
	in	a, ($00)
	cp	COMM_SM1_TEST_SWITCH_SM1_DENY
	jr	z, .switch_sm1_fail
	cp	COMM_SM1_TEST_SWITCH_SM1_DONE
	jr	z, .switch_sm1_done

	dec	bc
	ld	a, c
	or	b
	jr	nz, .loop_wait_switch_sm1

; switch didn't happen, return no error
.switch_sm1_fail:
	xor	a
	out	($00), a
	out	($0c), a
	ret

.switch_sm1_done:
	ld	a, $0
	out	($00), a
	out	($0c), a

	RCALL	sm1_oe_test
	jr	nz, .tests_end
	RCALL	sm1_crc32_test

.tests_end:
	; backup 'a' and have bios switch back to m1
	ld	b, a

	ld	a, COMM_SM1_TEST_SWITCH_M1
	out	($00), a
	out	($0c), a

.loop_wait_switch_m1:
	in	a, ($00)
	cp	COMM_SM1_TEST_SWITCH_M1_DONE
	jr	z, .switch_m1_done
	jr	.loop_wait_switch_m1

.switch_m1_done:
	ld	a, $0
	out	($00), a
	out	($0c), a
	ld	a, b
	and	a

	ret

; params:
;  bc  = start address
;  bc' = length
; returns:
;  bc = upper 16bits of crc32
;  de = lower 16bits of crc32
calc_crc32_psub:
	ld	a, c
	exx
	ld	l, a
	exx
	ld	a, b
	exx
	ld	h, a
	ld	d, b
	ld	e, c
	exx
	ld	de, $ffff
	ld	hl, $ffff

.loop_outer:
	ld	b, $08
	ld	a, e
	exx
	xor	(hl)
	inc	hl
	exx
	ld	e, a

.loop_inner:
	srl	h
	rr	l
	rr	d
	rr	e
	jr	nc, .next_loop_inner
	ld 	a, e
	xor	$20
	ld	e, a
	ld	a, d
	xor	$83
	ld	d, a
	ld	a, l
	xor	$b8
	ld	l, a
	ld	a, h
	xor	$ed
	ld	h, a

.next_loop_inner:
	djnz	.loop_inner
	exx
	dec	de
	ld	a, e
	or	d
	exx
	jr	nz, .loop_outer
	ld	a, e
	cpl
	ld	c, a
	ld	a, d
	cpl
	ld	b, a
	ld	a, l
	cpl
	ld	e, a
	ld	a, h
	cpl
	ld	d, a
	PSUB_RETURN

; The sm1 rom code resides within the first ~$5400 bytes of the rom,
; so we are only doing a crc32 check against those bytes.  Doing the
; entire rom would take an unreasonable amount of time, plus it would
; require adding a bunch of needless complexity doing bank switching
; to access the entire 128KB of the rom.
sm1_crc32_test:
	ld	bc, $0000
	exx
	ld	bc, SM1_CRC32_SIZE
	exx

	RCALL	calc_crc32_psub

	ld	hl, SM1_CRC32_UPPER
	sbc	hl, de
	jr	nz, .test_failed


	ld	hl, SM1_CRC32_LOWER
	sbc	hl, bc
	jr	nz, .test_failed

	xor	a
	ret

.test_failed
	ld	a, EC_Z80_SM1_CRC
	or	a
	ret

; output enable test for sm1 rom, mimics ram_oe_test
sm1_oe_test:
	ld	hl, $0000
	ld	de, $0000

	ld	b, $64
.loop_next:
	ld	a, (hl)
	cp	$7e		; ld a, (hl) opcode
	jr	nz, .loop_pass

	ld	a, (de)
	cp	$1a		; ld a, (de) opcode
	jr	z, .test_failed

.loop_pass:
	djnz	.loop_next
	xor	a
	ret

.test_failed:
	ld	a, EC_Z80_SM1_OE
	or	a
	ret

SM1_TEST_CODE_END:

; The first 32k of the m1 rom are used by the compiled code + mirrors.
; The remaining 96k of space is use for bank switching testing.  The
; last 4 bytes of every 2k are filled in with counter data.
; bank3 (16k) counter is at $fff and starts with $02
; bank2 (8k) counter is at $ffe and starts with $04
; bank1 (4k) counter is at $ffd and starts with $08
; bank0 (2k) counter is at $ffc and starts with $10
; In the rom file a banks counter is only increased for each new bank
; of its size,  meaning bank0's counter will increase for every 2k
; chunk, while bank3's counter would only increase every 8 2k chunks.
; The code below checks each possible bank location a bank can have
; within the 96k and makes sure those counters are correct.
rom_bank_tests:
	ld   	bc, $020b		; bank3 (16k)
	ld   	hl, $bfff		; offset within each bank to test
	ld   	e, $06			; number of 16k banks within the 96k
	call	test_rom_bank
	jr   	z, .test_passed_bank3
	ld   	a, EC_Z80_M1_BANK_ERROR_16K
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_bank3:
	ld	bc, $040a		; bank2 (8k)
	ld	hl, $dffe
	ld	e, $0c
	call	test_rom_bank
	jr	z, .test_passed_bank2
	ld	a, EC_Z80_M1_BANK_ERROR_8K
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_bank2:
	ld	bc, $0809		; bank1 (4k)
	ld	hl, $effd
	ld	e, $18
	call	test_rom_bank
	jr	z, .test_passed_bank1
	ld	a, EC_Z80_M1_BANK_ERROR_4K
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_bank1:
	ld	bc, $1008		; bank0 (2k)
	ld	hl, $f7fc
	ld	e, $30
	call	test_rom_bank
	jr	z, .test_passed_bank0
	ld	a, EC_Z80_M1_BANK_ERROR_2K
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_bank0:
	ret


; params
;  b = start
;  c = bank
;  hl = offset to test agains
;  e = number of banks to test
test_rom_bank:
	in	a, (c)
	ld	a, b
	cp	(hl)
	jr	nz, .test_failed_abort
	inc	b
	dec	e
	jr	nz, test_rom_bank
	xor	a
	ret

.test_failed_abort:
	xor	a
	inc	a
	ret

; returns:
;  Z = 0 (error), 1 = (pass)
;  a = error code or 0 if passed
ram_oe_test_psub:
	ld	hl, Z80_RAM_START
	ld	de, Z80_RAM_START

; When ram doesn't output anything on a read it usually results in the target
; register, 'a' for us, containing the opcode of the ld.  Its not 100% and
; will sometimes have $ff or other garbage, so we loop $64 times trying to
; catch 2 in a row with different ld opcodes
	ld	b, $64
.loop_next:
	ld	a, (hl)
	cp	$7e		; ld a, (hl) opcode
	jr	nz, .loop_pass

	ld	a, (de)
	cp	$1a		; ld a, (de) opcode
	jr	z, .test_failed

.loop_pass:
	djnz	.loop_next

	xor	a
	PSUB_RETURN

.test_failed:
	ld	a, EC_Z80_RAM_OE
	or	a
	PSUB_RETURN

; returns:
;  Z = 0 (error), 1 = (pass)
;  a = error code or 0 if passed
ram_we_test_psub:
	ld	hl, Z80_RAM_START

; read/save a byte from ram, write !byte back to the location,
; re-read the location and error if it still the original byte
	ld	a, (hl)
	ld	b, a
	xor	$ff
	ld	(hl), a
	ld	a, (hl)
	cp	b
	jr	z, .test_failed

	xor	a
	PSUB_RETURN

.test_failed:
	ld	a, EC_Z80_RAM_WE
	or	a
	PSUB_RETURN

; returns:
;  Z = 0 (error), 1 = (pass)
;  a = error code or 0 if passed
ram_data_tests_psub:
	ld	c, $00
	PSUB	test_ram_data
	jr	z, .test_passed_00
	ld	a, EC_Z80_RAM_DATA_00
	or   	a
	PSUB_RETURN

.test_passed_00:
	ld	c, $55
	PSUB	test_ram_data
	jr	z, .test_passed_55:
	ld	a, EC_Z80_RAM_DATA_55
	or	a
	PSUB_RETURN

.test_passed_55:
	ld   	c, $aa
	PSUB	test_ram_data
	jr   	z, .test_passed_aa:
	ld   	a, EC_Z80_RAM_DATA_AA
	or   	a
	PSUB_RETURN

.test_passed_aa:
	ld	c, $ff
	PSUB	test_ram_data
	jr	z, .test_passed_ff
	ld	a, EC_Z80_RAM_DATA_FF
	or	a
	PSUB_RETURN

.test_passed_ff:
	PSUB_RETURN

; returns:
;  Z = 0 (error), 1 = (pass)
;  a = error code or 0 if passed
ram_address_tests_psub:
	ld	bc, $0001
	PSUB	test_ram_address
	jr	z, .test_passed_a0_a7:
	ld	a, EC_Z80_RAM_ADDRESS_A0_A7
	or	a
	PSUB_RETURN

.test_passed_a0_a7:
	ld   	bc, $0100
	PSUB	test_ram_address
	jr   	z, .test_passed_a8_a10
	ld	a, EC_Z80_RAM_ADDRESS_A8_A10
	or   	a
	PSUB_RETURN

.test_passed_a8_a10:
	PSUB_RETURN


; params:
;  c = pattern
; returns:
;  a = 0 (pass), 1 (fail)
;  Z = 1 (pass), 0 (fail)
test_ram_data_psub:
	ld	hl, Z80_RAM_START	; ram start
	ld	a, c

.loop_next_address:
	ld	(hl), a
	cp	(hl)
	jr	nz, .test_failed_abort
	inc	l
	jr	nz, .loop_next_address
	inc	h
	jr	nz, .loop_next_address
	xor	a
	PSUB_RETURN

.test_failed_abort:
	xor	a
	inc	a
	PSUB_RETURN


; Write an incrementing data value at incrementing addresses, then
; read them back to verify the data matches
; params:
;  bc = incr address amount per loop
; returns:
;  a = 0 (pass), 1 (fail)
;  Z = 1 (pass), 0 (fail)
test_ram_address_psub:
	ld	d, b
	ld	e, c
	xor	a
	ld	b, a
	ld	hl, Z80_RAM_START

.loop_next_write_address:
	ld	(hl), a
	inc	a
	add	hl, de
	jr	c, .loop_start_read_address	; loop exits if we hit top of ram
	djnz	.loop_next_write_address	; or 256 iterations

.loop_start_read_address:
	xor	a
	ld	b, a
	ld	hl, Z80_RAM_START
.loop_next_read_address:
	cp	(hl)
	jr	nz, .test_failed_abort
	inc	a
	add	hl, de
	jr	c, .test_passed_done
	djnz	.loop_next_read_address

.test_passed_done:
	xor  a
	PSUB_RETURN

.test_failed_abort:
	xor  a
	inc  a
	PSUB_RETURN


m68k_comm_test_psub:
	ld	a, COMM_TEST_HELLO
	out	($0c), a
	out	($00), a

	; Wait up to 5 seconds (500 * 10ms) for a response to our hello.
	; If we were started at boot (AES or MV-1B/C) we need to allow a bit
	; of time for the main bios to run its tests before it will respond
	; to us.
	; Using bc' for our loop, bc will be used for the delay psub call.
	; We can't use de/hl because they are used to when setting up the
	; PSUB delay call.
	exx
	ld	bc, 500
	exx

	jp	.loop_start

.loop_again:
	ld	bc, 1540		; 1540 * 6.5us = ~10ms
	PSUB	delay

.loop_start:
	in	a, ($00)
	cp	COMM_TEST_HANDSHAKE
	jr	z, .got_handshake

	exx
	dec	bc
	ld	a, c
	or	b
	exx
	jr	nz, .loop_again

	or	$ff
	ld	a, EC_Z80_68K_COMM_NO_HANDSHAKE
	or	a
	PSUB_RETURN

.got_handshake:
	out	($00), a
	in	a, ($00)
	and	a
	jr	z, .test_passed
	ld	a, EC_Z80_68K_COMM_NO_CLEAR
	or	a
	PSUB_RETURN

.test_passed:
	ld	a, COMM_TEST_ACK
	out	($0c), a

	; delay a little to avoid sending an error before the m68k has had
	; time to consume our ACK
	ld	bc, 1540
	PSUB	delay

	xor	a
	PSUB_RETURN

ym2610_io_tests_psub:
	in	a, (YM2610_PORT0_REGISTER)
	rlca
	jr	c, .test_failed_abort		; ym2610 says its busy

	ld	a, $27
	out	(YM2610_PORT0_REGISTER), a	; irq/timer related register
	add	hl, hl				; delay
	add	hl, hl
	add	hl, hl
	add	hl, hl

	ld	a, $30
	out	(YM2610_PORT0_DATA), a		; disable irqs
	add	hl, hl				; delay
	add	hl, hl
	add	hl, hl
	add	hl, hl

	in	a, (YM2610_PORT0_REGISTER)
	and	$30				; check we get back what we wrote
	jr	nz, .test_failed_abort

; this next chunk of code writes $00/$55/$aa/$ff to reg $0 or ym2610 and
; re-reads it back to verify its the same
	ld	bc, $0000
	PSUB	ym2610_write_port0
	in	a, (YM2610_PORT0_DATA)
	cp	$00
	jr	nz, .test_failed_abort

	ld	bc, $5500
	PSUB	ym2610_write_port0
	in	a, (YM2610_PORT0_DATA)
	cp	$55
	jr	nz, .test_failed_abort

	ld	bc, $aa00
	PSUB	ym2610_write_port0
	in	a, (YM2610_PORT0_DATA)
	cp	$aa
	jr	nz, .test_failed_abort

	ld	bc, $ff00
	PSUB	ym2610_write_port0
	in	a, (YM2610_PORT0_DATA)
	cp	$ff
	jr	nz, .test_failed_abort
	xor	a
	PSUB_RETURN

.test_failed_abort:
	ld	a, EC_YM2610_IO_ERROR
	or	a
	PSUB_RETURN


; ym2610_io_tests disables the timer and interrupt generation
; on the ym2610.  Temp enable interrupts on the z80 to see
; if we get one.
ym2610_stuck_irq_test:
	ex	af, af'
	ld	a, YM2610_IRQ_UNEXPECTED
	ex	af, af'
	ei
	nop
	nop
	nop
	nop
	di
	ret

; setup the timer with irq's disabled, poll it
; and make sure it triggers within the expected range
ym2610_timer_flag_test:
	call	ym2610_timer_init
	ld	a, $ff
	jr	nz, .timer_init_failed:

	ld	bc, $0000
	ld	de, $4000

.loop_wait_timer_flag:
	in	a, (YM2610_PORT0_REGISTER)
	rrca
	jr	c, .timer_a_fired
	inc	bc
	dec	de
	ld	a, e
	or	d
	jr	nz, .loop_wait_timer_flag	; wait for the timer A flag to get set
	di					; indicating the timer fired

.test_failed_abort:
	or	$ff
	ld	a, EC_YM2610_TIMER_TIMING_FLAG
	or	a
	ret

.timer_init_failed:
	or	$ff
	ld	a, EC_YM2610_TIMER_INIT_FLAG
	or	a
	ret

; The timer fired now make sure it was within the
; range we were expecting
.timer_a_fired:
	di
	ld	hl, $02a5
	cp	a
	sbc	hl, bc
	jr	z, .test_passed_greater
	jr	nc, .test_failed_abort

.test_passed_greater:
	ld	hl, $02af
	cp	a
	sbc	hl, bc
	jr	c, .test_failed_abort
	xor	a
	ret


; Test the timer with irq's enabled
ym2610_timer_irq_test:
	call	ym2610_timer_init
	jr	nz, .timer_init_failed

	ex	af, af'
	ld	a, YM2610_IRQ_EXPECTED
	ex	af, af'

	ei

	ld	bc, $0000
	ld	l, $00
	ld	de, $4000

.loop_wait_int:
	ld	a, l		; when an irq fires it will cause l to be $ff
	or	a
	jr	nz, .got_ym2610_int
	inc	bc
	dec	de
	ld	a, e
	or	d
	jr	nz, .loop_wait_int
	di

.test_failed_abort:
	ld	a, EC_YM2610_TIMER_TIMING_IRQ
	or	a
	ret

.timer_init_failed:
	ld	a, EC_YM2610_TIMER_INIT_IRQ
	or	a
	ret

; make sure bc is between $30a and $314 for how long
; it took for the irq to fire
.got_ym2610_int:
	di
	ld	hl, $030a
	cp	a
	sbc	hl, bc
	jr	z, .test_passed_greater
	jr	nc, .test_failed_abort

.test_passed_greater:
	ld	hl, $0314
	cp	a
	sbc	hl, bc
	jr	c, .test_failed_abort
	xor	a
	ret


ym2610_timer_init:
	ld	de, $3027		; reset TA/TB flags
	call	ym2610_write_port0
	jr	nz, .init_timeout

	ld	de, $0025		; clear TA counter LSBs
	call	ym2610_write_port0
	jr	nz, .init_timeout

	ld	de, $8024		; set TBA MSBs to $80
	call	ym2610_write_port0
	jr	nz, .init_timeout

	ld	de, $0527		; enable TA irq, load TA
	call	ym2610_write_port0
	jr	nz, .init_timeout
	ret

.init_timeout:
	ret

run_subroutine_tests:
	ld	sp, $fffd	; init stack pointer

	call	ym2610_stuck_irq_test

	call	ym2610_timer_flag_test
	jr	z, .test_passed_ym2610_timer_flag_test
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ym2610_timer_flag_test:
	call 	ym2610_timer_irq_test
	jr	z, .test_passed_ym2610_timer_irq_test
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_ym2610_timer_irq_test:

	call	rom_bank_tests			; will call play_z80_error_code_stall itself
	call	sm1_tests
	jr	z, .test_passed_sm1_tests
	rst	RST_HANDLE_Z80_ERROR_CODE

.test_passed_sm1_tests:
	PSUB	ym2610_make_noise

	ld	a, COMM_Z80_TESTS_COMPLETE	; tell 68k we are done with tests
	out	($0c), a

.loop_wait_68k_error_code:
	in	a, ($00)
	and	a
	jr	z, .loop_wait_68k_error_code
	ld	c, a
	in	a, ($00)
	cp	c
	jr	nz, .loop_wait_68k_error_code
	jp	handle_68k_error_code
	jr	.loop_wait_68k_error_code

	rorg	$07fb, $ff
ROM_MIRROR_OFFSET:
	dc.b	$00
ROM_CRC32_OFFSET:
	dc.b	$00,$00,$00,$00
