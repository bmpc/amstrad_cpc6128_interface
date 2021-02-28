; getfile - transfers a file from Arduino to CPC

UseTestData    equ 0                ; 1 - use test data; 0 - use real IO 

cas_out_open   equ &bc8c
cas_out_close  equ &bc8f
cas_out_char   equ &bc95

PrintChar      equ &BB5A

filename_size  equ &8000


	org &8100

SendCmd:
	ld a, 2                       ; Load GETFILE cmd into accumulator
	call SendControlByte          ; Send GETFILE command

	ld hl, filename_size
	ld c, (hl)                    ; load C with filename size
	ld de, filename_size + 1
SendFilenameByte:
	ld a, (de)                     ; load A with filename byte
	
	push bc
		call SendDataByte
	pop bc

	inc de
	dec c                         ; decrement filename pos
	jr nz, SendFilenameByte       ; if C != 0 -> keep sending filename bytes

	ld a, 0                       ; send \0 after filename
	call SendDataByte            

	call RecvControlByte          ; Receive filename result
	cp 0
	jp z, PrintFileNotFound       ; Print FileNotFound message in case of 0 message from control port

	call RecvDataByte             ; Receive file size high byte
	ld b, a

	call RecvDataByte             ; Receive file size low byte
	ld c, a

OpenOutFile:
	push bc
		ld hl, filename_size
		ld b, (hl)                    ; load B with filename size
		ld hl, filename_size + 1      ; load HL with filename start position
		ld de, two_k_buffer           ; pass the 2k buffer
		call cas_out_open             ; open output file
	pop bc

next_byte:
	call RecvDataByte             ; Read byte from IO
	push bc
	push hl
		call cas_out_char         ; write byte to output file
	pop hl
	pop bc
	
	dec bc                        ; decrement count (BC = number of bytes remaining to write to output file)
 
	ld a, b
	or c
	jr nz, next_byte 			  ; BC <> 0 -> not finished. write more bytes

	call cas_out_close            ; BC = 0 -> finished writing - close the output file
	ret                           ; Finish!


; Prints File not found! message screen
PrintFileNotFound:
	ld hl,FileNotFound           ; load empty string mem loc into HL
	call PrintString
	call NewLine
	ret                          ; end program

; Print a '255' terminated string
PrintString:
	ld a, (hl)                   ; load memory referenced by HL into register A
	cp 255                       ; Compare byte with 255
	ret z                        ; return if A == 255
	inc hl                       ; increment HL
	call PrintChar
	jr PrintString
    
NewLine:
    ld a,13                      ; Carriage return
    call PrintChar
    ld a,10                      ; Line Feed
    jp PrintChar


#if UseTestData
SendDataByte:
	jp TestSendDataByte
SendControlByte:
	jp TestSendControlByte
RecvDataByte:
	jp TestRecvDataByte
RecvControlByte:
	jp TestRecvControlByte

; Test Routine for sending message - does nothing
TestSendControlByte:
TestSendDataByte:
	ret

; Test Routine for receiving byte. Instead of using IO, it will fetch the data from the 'TestData' var
TestRecvControlByte:
TestRecvDataByte:
	push hl                        ; push registers HL, BC, and DE into stack
	push bc
	push de

		ld hl,TestData             ; load HL register with TestData address
		ld bc,TestDataPos          ; load BC register with TestDataPos address

		ld d,0                     ; Load DE register pair with the current memory position of the Test data
		ld a,(bc)
		ld e,a
		add hl,de

		inc a
		ld (bc), a

		ld a, (hl)                 ; load A register with the result byte

	pop de                         ; pop registers HL, BC, and DE from stack
	pop bc
	pop hl
	
	ret

#else

SendDataByte:
	jp DoSendDataByte
SendControlByte:
	jp DoSendControlByte
RecvDataByte:
	jp DoRecvDataByte
RecvControlByte:
	jp DoRecvControlByte

DoSendDataByte:
	ld c, &d0                      ; Load C with low port byte
	ld b, &fb                      ; Load D with high port byte
	out (c), a                     ; Send the DATA byte
	ret

DoSendControlByte:
	ld c, &d1                      ; Load C with low port byte
	ld b, &fb                      ; Load D with high port byte
	out (c), a                     ; Send CONTROL byte
	ret

DoRecvDataByte:
	ld a, &fb                      ; Load A with high port byte
	in a, (&d0)                    ; Read byte from IO data port

	ret

DoRecvControlByte:
	ld a, &fb                      ; Load A with high port byte
	in a, (&d1)                    ; Read byte from IO control port

	ret
	
#endif

FileNotFound:
	db "File not found!", 255

;;----------------------------------------------------------------
;; this is the filename of the output file

filename:
	defb "datafile.bin"
end_filename

;;----------------------------------------------------------------
;; this buffer is filled with data which will be written to the output file

two_k_buffer 
	defs 2048

#if UseTestData
TestData:
    ; FileNotFound?, FileSize high byte, FileSize low byte, FileData
	db 1,1,0,0,84,69,83,84,32,32,32,32,66,65,83,0,0,0,0,0,0,0,0,0,112,1,0,21,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,0,0,49,3,19,0,10,0,191,34,66,114,117,110,111,32,67,111,110,100,101,34,0,0,0,26,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,19,0,10,0,191,34,66,114,117,110,111,32,67,111,110,100,101,34,0,0,0,26,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,97,26,160,32,30,20,0,0,0,0,26,32,3,0,0,225,1,190,32,13,0,0,233,44,255,29,40,34,38

TestDataPos:
	db 0
#endif
