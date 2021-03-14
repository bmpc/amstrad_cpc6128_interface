; dir - list all available files

UseTestData   equ 0                ; 1 - use test data; 0 - use real IO 

PrintChar     equ &BB5A
WaitChar      equ &BB06

	org &8000

SendDirCmd:
	ld a, 1                        ; Load DIR cmd into accumulator
	call SendControlByte           ; Send DIR command


NextFile:
	call RecvControlByte
	cp 1                           ; if we receive 1 from the control port, then we can start receiving the response
	jr nz, Finish
	
	call RecvFile
	
	ld a, (Count)
	inc a
	ld (Count), a                  ; if there are more than 255 files, this will fail miserably 

	jr NextFile

Finish:
	ld a, (Count)
	cp 0
	jp z,PrintEmpty 	           ; A = 0 -> No files in directory -- Jump to empty msg
	
	ret                            ; end program

#if UseTestData
SendByte:
	jp TestSendByte
SendControlByte:
	ret
RecvByte:
	jp TestRecvByte
RecvControlByte:
	jp TestRecvControlByte

; Test Routine for sending message - does nothing
TestSendByte:
	ret

; Test Routine for receiving byte. Instead of using IO, it will fetch the data from the 'TestData' var
TestRecvByte:
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

TestRecvControlByte:
	ld a, (TestDataCount)
	cp 4
	ret z                          ; return if A == 4
	inc a
	ld (TestDataCount), a          ; store incremented TestDataCount
	ld a, 1						   ; return a with 1
	ret

#else

SendControlByte:
	jp DoSendControlByte
RecvByte:
	jp DoRecvByte
RecvControlByte:
	jp DoRecvControlByte

DoSendControlByte:
	ld c, &d1                      ; Load C with low port byte
	ld b, &fb                      ; Load D with high port byte
	out (c), a                     ; Send DIR cmd
	ret

DoRecvByte:
	ld a, &fb                      ; Load A with high port byte
	in a, (&d0)                    ; Read byte from IO data port

	ret

DoRecvControlByte:
	ld a, &fb                      ; Load A with high port byte
	in a, (&d1)                    ; Read byte from IO control port

	ret

#endif

; Receive file name in the form: XXXXXXXXEEESF where: 
;   - X represents filename chars, 
;   - E file extension chars, 
;   - S the size of the file in KB,
;   - F if the source filename is invalid - TODO
RecvFile:
	ld hl,FileName                 ; load HL register pair with initial loc of FileName var
	ld b,11                        ; expect exactly 11 chars in filename + extension
RecvFileName:
	call RecvByte                  ; receive byte from file name
	ld (hl),a                      ; load filename var with received byte from A register
	inc hl                         ; increment HL 
	dec b                          ; decrement b (filename + extension)
	ld a,b                         ; Load register B into Accumulator
	cp 3                           ; have we reached 3 (extension)?
	call z, FileExtensionSep       ; if A == 3 -> add '.' to file name buffer
	cp 0                           ; have we reached 0?
	jr nz, RecvFileName            ; if A != 0 -> keep receiving bytes
	call RecvByte                  ; Receive byte with file size
	ld hl,FileSize                 ; load HL register pair with FileSize var
	ld (hl),a                      ; store file size var

	call PrintFileInfo

	ret

; Add '.' between file name and extension
FileExtensionSep:
	inc hl
	ld a,'.'                       ; Add a '.' between the filename and extension - Load A with '.'
	ld ix, FileName
	ld (ix+9),a                    ; Store '.' in filename
	ret

; Prints the file name and size to the screen
PrintFileInfo:
	ld hl,FileName                 ; load HL register pair with initial loc of FileName var 
	call PrintString              
	
	ld a, ' '                      ; Add spaces between filename and extension
	call PrintChar
	call PrintChar
	call PrintChar
	call PrintChar

	; convert the file size byte in memory to ASCII
	ld bc,FileSize                 ; load BC register pair the FileSize var loc
	ld a,(bc)                      ; Load A with BC register - contains file size
	ld h,0                         ; load H with 0 - High
	ld l,a                         ; load L with A - Low - file size
	ld de,FileSizeDec              ; load DE register with the FileSizeDec var loc - mem to store the converted string
	call Num2Dec

	ld hl,FileSizeDec              ; load HL register pair the FileSizeDec var loc
	call PrintString
	ld a, 'K'                      ; Load 'K' into A register
	call PrintChar
	call NewLine

	ret

; Prints the no files msg to the screen
PrintEmpty:
	ld hl,Empty                    ; load empty string mem loc into HL
	call PrintString
	call NewLine
	ret                            ; end program

; Prints the not connected/timeout message screen
PrintTimeout:
	ld hl,Timeout                    ; load empty string mem loc into HL
	call PrintString
	call NewLine
	ret                            ; end program

; Print a '255' terminated string
PrintString:
	ld a, (hl)                     ; load memory referenced by HL into register A
	cp 255                         ; Compare byte with 255
	ret z                          ; return if A == 255
	inc hl                         ; increment HL
	call PrintChar
	jr PrintString
    
NewLine:
    ld a,13                        ; Carriage return
    call PrintChar
    ld a,10                        ; Line Feed
    jp PrintChar

; 16-bit Integer to ASCII (decimal) - adapted from http://map.grauw.nl/sources/external/z80bits.html
Num2Dec:
	ld bc,-10000
	call Num1
	ld bc,-1000
	call Num1
	ld bc,-100
	call Num1
	ld c,-10
	call Num1
	ld c,b
Num1:
	ld a,'0'-1
Num2:
	inc a
	add hl,bc
	jr c,Num2
	sbc hl,bc

	cp a,'0'                       ; replace leading zeros with spaces
	jr nz, Num3
	ld a,' '
Num3:
	ld (de),a
	inc de
	ret

Empty:
	db 'No files in directory.', 255

Timeout:
	db 'Timeout!',13,10,'Is the Arduino connected to the CPC?', 255

FileName:
	db 'XXXXXXXX.XXX',255

FileSize:
	db 0

FileSizeDec:
	db '00000',255

Count:
	db 0

#if UseTestData
TestData:
	db 'FILEA   BAS',3,'FILEB   BIN',12,'BRUNO   BAS',1,'CONDE   BIN',5

TestDataPos:
	db 0

TestDataCount:
	db 0
#endif