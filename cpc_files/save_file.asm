file_size     equ 100
cas_out_open  equ &bc8c
cas_out_close equ &bc8f
cas_out_char  equ &bc95

	org &8000
	
	ld b,end_filename-filename
	ld hl,filename
	ld de,two_k_buffer
	call cas_out_open             ; open output file
	
	ld bc, file_size              ; BC contains the number of bytes to read and write to file

next_byte:
	ld a, &fb                     ; Load A with high port byte
	in a, (&d0)				 	  ; Read byte from IO
	push bc
	call cas_out_char             ; write byte to output file
	pop bc
	dec bc                        ; decrement count (BC = number of bytes remaining to write to output file)
 
	ld a,b
	or c
	jr nz,next_byte 			  ; BC <> 0 -> not finished. write more bytes

	call cas_out_close            ; BC = 0 -> finished writing - close the output file
	ret

;;----------------------------------------------------------------
;; this is the filename of the output file

filename:
	defb "datafile.bin"
end_filename

;;----------------------------------------------------------------
;; this buffer is filled with data which will be written to the output file

two_k_buffer 
	defs 2048