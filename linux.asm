format	ELF64 executable 3
entry	start

segment writable executable

include	"x86-64.asm"

; Startup 4th code
text:
file	"4th/parsing.4th"
file	"4th/control-flow.4th"
file	"4th/io.4th"
text_size = $ - text

CODE	"bye",bye
	mov	edi, ebx		; exit code
	mov	eax, SYS_EXIT
	syscall
	ud2

CODE	"type", type
	mov	eax, SYS_WRITE
	mov	edi, 1			; stdout
	mov	edx, ebx		; count
	mov	ebx, esi
	pop	rsi			; data
	syscall
	mov	esi, ebx
	pop	rbx
	NEXT

CODE	"accept", accept
	mov	eax, SYS_READ
	mov	edi, 0			; stdin
	mov	edx, ebx		; count
	mov	ebx, esi
	pop	rsi			; buffer
	syscall
	mov	esi, ebx
	mov	ebx, eax		; count
	NEXT

dictionary_end = dictionary

start:
	mov	esi, 4096
	call	mmap_page
	lea	rbp, [rax + 4096]	; return stack

	mov	esi, 4096
	call	mmap_page
	lea	rsp, [rax + 4096]	; parameter stack

	mov	esi, 8192
	call	mmap_page
	mov	[var_data_pointer], eax

	mov	dword [var_tib], text
	mov	dword [var_ntib], text_size

	lea	esi, [thread]
	NEXT

	align	4
thread:
	dd	_interpret
	dd	_quit

SYS_READ = 0
SYS_WRITE = 1
SYS_MMAP = 9
SYS_EXIT = 60
PROT_WRITE = 0x2
PROT_EXEC = 0x4
MAP_PRIVATE = 0x2
MAP_ANONYMOUS = 0x20
MAP_32BIT = 0x40

mmap_page:
	mov	eax, SYS_MMAP
	xor	edi, edi		; No hint
	mov	edx, PROT_EXEC or PROT_WRITE
	mov	r10d, MAP_PRIVATE or MAP_32BIT or MAP_ANONYMOUS
	or	r8d, -1			; No fd
	xor	r9, r9			; No offset
	syscall
	test	rax, rax
	js	abort
	ret

abort:
	mov	eax, SYS_EXIT
	or	edi, -1
	syscall
	ud2
