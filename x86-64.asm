; Forth implementation for 64 bit x86 processor

; This file defines core behaviour, including all built in code words

; ITC forth, threads look like:
;
;            IP --|
;                 v
;        -----+-------+-------+-----
;        ...  | token | token |  ...
;        -----+-------+-------+-----
;                 |
;                 | W
;                 v
;   +------+------------+------------------
;   | link | code field | parameter field   ...
;   +------+------------+------------------
;                 |
;                 v
;            +----------------
;            |  machine code  ...
;            +----------------
;
; Each token is a single cell (4-byte) value
;
; We use the following global registers for forth code
;  ESI - instruction pointer
;  EBX - top of stack
;  ESP - parameter stack pointer
;  EBP - return stack pointer
;
; Additionally, EAX is used as the temporary working register 'W'
; It contains the code field address if the current word.

; NEXT - the inner interpreter

macro NEXT {
	lodsd				; W = (IP), IP++
	jmp	qword [rax]		; jump (W)
}

; Push and pop to the return stack. This uses rbp instead of the hardware stack

macro PUSHRSP val* {
	sub	ebp, 4
	mov	dword [rbp], val
}

macro POPRSP dest* {
	mov	dest, dword [rbp]
	add	ebp, 4
}

; Dictionary entry structure:
;
;   Link	4 bytes		Pointer to previous entry
;   Flags	1 byte
;	Imm	1 bit		1 = immediate word
;	Hid	1 bit		0 = visible, 1 = hidden
;   Len		1 byte		Length of name of word
;   Name	Len bytes	Name of word
;   (padding to 8 bytes)
;   Code field	8 bytes		Pointer to machine code routine
;   Parameter	(remainder)	Data for word
;
;   +--------------------+
;   |        Link        |
;   +--------------------+
;   | F | L | name...    |
;   |---+---+            |
;   |                    |
;   +--------------------+
;   |     code field     |
;   +--------------------+
;   |  parameter field   |
;   |        ...         |
;

; Initial dictionary. Words defined here are:
; - Core code words, i.e. not implementable in pure forth
; - Performance-sensitive words, implemented in assembly for speed
; - Colon definitions needed to bootstrap the interpreter

dictionary = 0

macro HEADER name*, xt_name*, flags=0 {
	align	4
	dd	dictionary		; Push into linked list
	dictionary = $ - 4		; New head of list
	db	flags
	db	@f - $ - 1		; Name length
	db	name			; Search name
@@:
	align	8
_#xt_name:
}

macro CODE name*, xt_name* {
	HEADER	name, xt_name
	dq	$ + 8
code_#xt_name:
}

; Code primitives

; Stack manipulation routines

CODE	"dup", dup
	; ( n -- n n )
	push	rbx
	NEXT

CODE	"drop", drop
	; ( n -- )
	pop	rbx
	NEXT

CODE	"swap", swap
	; ( n1 n2 -- n2 n1 )
	xchg	ebx, [rsp]
	NEXT

CODE	"rot", rot
	; ( rcx rax rbx -- rax rbx rcx )
	pop	rax
	pop	rcx
	push	rax
	push	rbx
	mov	ebx, ecx
	NEXT

CODE	"over", over
	; ( n1 n2 -- n1 n2 n1 )
	push	rbx
	mov	ebx, [rsp + 8]
	NEXT

CODE	"nip", nip
	; ( n1 n2 -- n2 )
	add	esp, 8
	NEXT

CODE	"tuck", tuck
	; ( n1 n2 -- n2 n1 n2 )
	mov	eax, [rsp]		; n1
	mov	[rsp], ebx		; n2
	push	rax			; n1
	NEXT

CODE	"2dup", two_dup
	mov	eax, [rsp]
	push	rbx
	push	rax
	NEXT

CODE	"2drop", two_drop
	pop	rbx
	pop	rbx
	NEXT

CODE	"sp@", sp_fetch
	push	rbx
	mov	ebx, esp
	NEXT

CODE	"sp!", sp_store
	mov	esp, ebx
	pop	rbx
	NEXT

; Return stack operations

CODE	">r", to_r
	PUSHRSP	ebx
	pop	rbx
	NEXT

CODE	"r>", r_from
	push	rbx
	POPRSP	ebx
	NEXT

CODE	"r@", r_fetch
	push	rbx
	mov	ebx, [rbp]
	NEXT

CODE	"2r>", two_r_from
	push	rbx
	mov	eax, [rbp + 4]
	push	rax
	mov	ebx, [rbp]
	add	rbp, 8
	NEXT

CODE	"2>r", two_to_r
	sub	rbp, 8
	mov	[rbp], ebx
	pop	rax
	mov	[rbp + 4], eax
	pop	rbx
	NEXT

CODE	"rp@", rp_fetch
	push	rbx
	mov	ebx, ebp
	NEXT

CODE	"rp!", rp_store
	mov	ebp, ebx
	pop	rbx
	NEXT

; Memory operations

CODE	"@", fetch
	mov	ebx, [rbx]
	NEXT

CODE	"!", store
	pop	rax
	mov	[rbx], eax
	pop	rbx
	NEXT

CODE	"+!", plus_store
	pop	rax
	add	[rbx], eax
	pop	rbx
	NEXT

CODE	"1+!", one_plus_store
	inc	dword [rbx]
	pop	rbx
	NEXT

CODE	"c@", c_fetch
	mov	bl, [rbx]
	movzx	ebx, bl
	NEXT

CODE	"c!", c_store
	pop	rax
	mov	[rbx], al
	pop	rbx
	NEXT

CODE	"@!", fetch_store
	; : @! ( x1 addr -- x2 ) dup @ -rot ! ;
	pop	rax
	xchg	eax, [rbx]
	mov	ebx, eax
	NEXT

; Byte manipulation

memcpy:
	mov	rax, rdi
	mov	rcx, rdx
	rep movsb
	ret

memmove:
	cmp	rdi, rsi		; If dest <= source
	jbe	memcpy			; ... do fast low-to-high copy
	lea	rcx, [rsi + rdx]	; End of source buffer
	cmp	rdi, rcx		; If buffers not overlapped
	jae	memcpy			; ... do fast copy

	mov	r8, rdi			; Save dest
	sub	rdx, 1
	js	.done
.loop:
	mov	al, [rsi + rdx]
	mov	[rdi + rdx], al
	sub	rdx, 1
	jns	.loop
.done:
	mov	rdi, r8
	ret

CODE	"move", move
	; ( src dst u -- )
	mov	edx, ebx		; count
	pop	rdi			; dst
	mov	ebx, esi		; saved IP
	pop	rsi			; src
	call	memmove
	mov	esi, ebx		; saved IP
	pop	rbx			; new TOS
	NEXT

memset:
	mov	rcx, rdx
	mov	rdx, rdi
	mov	al, sil
	rep stosb
	mov	rax, rdx
	ret

CODE	"fill", fill
	; ( dst u char -- )
	pop	rdx			; count
	pop	rdi			; dst
	xchg	esi, ebx		; IP, TOS
	call	memset
	mov	esi, ebx
	pop	rbx
	NEXT

memcmp:
	xor	eax, eax
	mov	rcx, rdx
	repe cmpsb
	jb	.less
	ja	.greater
	ret
.less:
	inc	eax
	ret
.greater:
	dec	eax
	ret

CODE	"memcompare", memcompare
	; ( p1 p2 len -- 1|0|-1 )
	mov	edx, ebx		; len
	mov	ebx, esi		; Saved IP
	pop	rdi			; p2
	pop	rsi			; p1
	call	memcmp
	mov	esi, ebx
	mov	ebx, eax
	NEXT

; Arithmetic

macro BINOPP name*, xt_name*, opp* {
CODE	name, xt_name
	pop	rax
	opp	ebx, eax
	NEXT
}

BINOPP	"+", plus, add
BINOPP	"*", times, imul
BINOPP	"or", or, or
BINOPP	"xor", xor, xor
BINOPP	"and", and, and

CODE	"-", minus
	mov	eax, ebx
	pop	rbx
	sub	ebx, eax
	NEXT

CODE	"max", max
	pop	rax
	cmp	ebx, eax
	cmovl	ebx, eax
	NEXT

CODE	"min", min
	pop	rax
	cmp	ebx, eax
	cmovg	ebx, eax
	NEXT

CODE	"2*", two_times
	sal	ebx, 1
	NEXT

macro UNARYOPP name*, xt_name*, opp* {
CODE	name, xt_name
	opp	ebx
	NEXT
}

UNARYOPP	"1+", one_plus, inc
UNARYOPP	"1-", one_minus, dec
UNARYOPP	"negate", negate, neg
UNARYOPP	"invert", invert, not

macro UNARYCOMP name*, xt_name*, opp* {
CODE	name, xt_name
	test	ebx, ebx
	opp	bl
	movzx	ebx, bl
	NEXT
}

UNARYCOMP	"0=", zero_equals, sete
UNARYCOMP	"0<>", zero_not_equals, setne
UNARYCOMP	"0<", zero_less, sets
UNARYCOMP	"0>", zero_greater, setg

macro BINCOMP name*, xt_name*, opp* {
CODE	name, xt_name
	pop	rax
	cmp	eax, ebx
	opp	bl
	movzx	ebx, bl
	NEXT
}

BINCOMP	"=", equals, sete
BINCOMP	"<>", not_equals, setne
BINCOMP	"<", less, setl

CODE	"aligned", aligned
	add	ebx, 3
	and	ebx, -4
	NEXT

CODE	"2aligned", two_aligned
	add	ebx, 7
	and	ebx, -8
	NEXT

; Basic text-number conversions

CODE	"str>num", str_to_num
	; ( caddr u -- n 1 | 0 )
	; (edi ptr) (eax converted) (ebx len) (cl char) (dl sign flag) (r8d base)
	pop	rdi			; ptr num
	test	ebx, ebx		; if length = 0
	jz	.reject			;    then abort

	xor	eax, eax		; conversion result
	mov	r8d, [var_base]

	xor	edx, edx		; sign bit, start positive
	mov	cl, [rdi]		; lead character
	cmp	cl, '-'			; if doesn't start with '-'
	jne	.positive		;    then don't set sign bit
	inc	edx			; set sign bit
	inc	edi			; skip sign char
	dec	ebx
	jz	.reject			; if length = 0 then abort
.positive:
	xor	ecx, ecx		; zero upper part of cl
.loop:
	mov	cl, [rdi]		; next character
	sub	cl, '0'
	cmp	cl, 'a'-'0'		; if the character is alphabetic
	jb	@f
	sub	cl, 'a'-'0'-10		; then subtract 'a' to get offset
@@:	cmp	ecx, r8d		; if out of range of digits
	jae	.reject			;    then reject

	imul	r8d
	add	eax, ecx

	inc	edi
	dec	ebx
	jne	.loop

	test	dl, dl			; if sign bit set
	je	@f
	neg	eax			; then negate return value
@@:     push	rax			; return conversion result
	mov	ebx, 1			; success flag
	NEXT
.reject:
	xor	ebx, ebx		; fail flag
	NEXT

CODE	"num>str", num_to_str
	; ( n caddr -- caddr u )
	; (ebx ptr) (edx:eax quotient/remainder) (r8d base) (r9l sign) (cl char) (edi len)
	xor	edi, edi		; Output length = 0
	add	ebx, 16			; Reserve characters for output
	mov	r8d, [var_base]		; Base
	pop	rax			; Number to convert

	mov	cl, ' '
	call	.put

	xor	r9d, r9d		; start positive
	test	eax, eax		; If number positive
	jns	.loop			;    skip to loop
	neg	eax
	inc	r9d			; Set sign flag
.loop:
	xor	edx, edx
	div	r8d			; edx = num % base, eax = num / base
	lea	ecx, [rdx + '0']
	cmp	edx, 10			; should we use 0-9?
	jl	@f
	add	cl, 'a'-'0'-10		; use a-z instead of 0-9
@@:	call	.put			; prepend to str
	test	eax,eax			; If not zero
	jnz	.loop			;    continue to next digit

	test	r9b, r9b		; Test for sign
	jz	.done
	mov	cl, '-'
	call	.put

.done:
	inc	ebx
	xchg	ebx, edi
	push	rdi
	NEXT

.put:
	mov	[rbx], cl
	dec	ebx
	inc	edi
	ret

; Control flow

CODE	"branch", branch
	mov	esi, [esi]
	NEXT

CODE	"0branch", 0branch
	test	ebx, ebx
	pop	rbx
	jz	code_branch
	add	esi, 4
	NEXT

CODE	"?dup", question_dup
	test	ebx, ebx
	jz	@f
	push	rbx
@@:	NEXT

CODE	"execute", execute
	mov	eax, ebx
	pop	rbx
	jmp	qword [rax]

; Looping constructs

CODE	"(loopi)", loop_inc
	inc	dword [rbp]
	NEXT

CODE	"(?loop)", loop_test
	mov	eax, [rbp + 4]
	cmp	eax, [rbp]
	jne	code_branch
	add	esi, 4
	NEXT

CODE	"unloop", unloop
	add	ebp, 8
	NEXT

CODE	"(of)", of
	pop	rax
	cmp	eax, ebx
	je	@f
	mov	ebx, eax
	jmp	code_branch
@@:	pop	rbx
	add	esi, 4
	NEXT

; Colon definitions, high level words

code_docolon:
	PUSHRSP	esi			; Save instruction pointer
	lea	esi, [rax + 8]		; Parameter field address
	NEXT

CODE	"exit", e
	POPRSP	esi			; Restore instruction pointer
	NEXT

CODE	"(lit)", l
	push	rbx
	lodsd
	mov	ebx, eax
	NEXT

code_dovar:
	push	rbx
	lea	ebx, [rax + 8]		; Parameter field address
	NEXT

code_doconst:
	push	rbx
	mov	ebx, [rax + 8]		; Parameter field contents
	NEXT

code_dodefer:
	mov	eax, [rax + 8]
	jmp	qword [rax]


macro COLON name*, xt_name*, flags=0 {
	HEADER	name, xt_name, flags
	dq	code_docolon
}

macro VARIABLE name*, xt_name*, value* {
	HEADER	name, xt_name
	dq	code_dovar
var_#xt_name:
	dd	value
}

macro CONSTANT name*, xt_name*, value* {
	HEADER	name, xt_name
	dq	code_doconst
	dd	value
}

macro ALIAS name*, xt_name*, target* {
	HEADER	name, xt_name
	dq	code_dodefer
	dd	target
}


COLON	"double",double
	dd	_dup, _plus, _e

; Enough colon definitions to bootstrap the interpreter.
; These are hand-translated from interpreter.4th

; 'addr u' string operations

COLON	"/string", slash_string
	dd	_tuck, _minus, _to_r, _plus, _r_from, _e

COLON	"count", count
	dd	_dup, _one_plus, _swap, _c_fetch, _e

COLON	"string-for", string_for
	dd	_over, _plus, _swap, _e

; Data space access. The actual value of data-pointer needs
; to be set first at startup before usage

COLON	"here", here
	dd	_data_pointer, _fetch, _e

COLON	",", comma
	dd	_here, _store, _l, 4, _data_pointer, _plus_store, _e

COLON	"align", align
	dd	_here, _aligned, _data_pointer, _store, _e

; Literals

COLON	"literal", literal, 1
	dd	_l, _l, _comma, _comma, _e

; Dictionary token (aka name token) manupulation

ALIAS	"dt>next", dt_next, _fetch

COLON	"dt>name", dt_name
	dd	_l, 5, _plus, _e

COLON	"dt>xt", dt_xt
	dd	_dt_name, _dup, _c_fetch, _plus, _one_plus, _two_aligned, _e

COLON	"dt-immediate>", dt_immediate
	dd	_l, 4, _plus, _c_fetch, _l, 1, _and, _e

COLON	"dt<>", dt_neq
	dd	_dt_name, _dup, _c_fetch, _one_plus, _memcompare, _zero_not_equals, _e

; Dictionary lookups

COLON	"latest", latest
	dd	_dict, _fetch, _e

COLON	"lookup", lookup
	dd	_latest
.loop:	dd	_dup, _0branch, .done
	dd	_two_dup, _dt_neq, _0branch, .done
	dd	_dt_next, _branch, .loop
.done:	dd	_nip, _e

COLON	"lookup-buffer", lookup_buffer
	dd	_here, _dt_name, _e

COLON	"prepare-word", prepare_word
	dd	_align, _lookup_buffer, _to_r
	dd	_l, 30, _min
	dd	_dup, _r_fetch, _c_store
	dd	_r_fetch, _one_plus, _swap, _move, _r_from, _e

COLON	"find", find
	dd	_dup, _lookup, _dup, _0branch, .end
	dd	_nip, _dup, _dt_xt, _swap
	dd	_dt_immediate, _two_times, _one_minus
.end:	dd	_e

COLON	"'", tick
	dd	_bl, _word, _find, _0branch, @f, _e
@@:	dd	_l, -13, _bye

; Input and Parsing

COLON	"source", source
	dd	_tib, _fetch, _ntib, _fetch, _e

COLON	"parse-area", parse_area
	dd	_source, _to_in, _fetch, _slash_string, _e

COLON	"parse-skip", parse_skip
	dd	_parse_area, _string_for, _two_to_r, _branch, .test
.loop:	dd	_dup, _r_fetch, _c_fetch, _equals, _0branch, .done
	dd	_to_in, _one_plus_store, _loop_inc
.test:	dd	_loop_test, .loop
.done:	dd	_unloop, _drop, _e

COLON	"parse-until", parse_until
	dd	_parse_area, _string_for, _two_to_r, _branch, .test
.loop:	dd	_dup, _r_fetch, _c_fetch, _not_equals, _0branch, .done
	dd	_to_in, _one_plus_store, _loop_inc
.test:	dd	_loop_test, .loop
.done:	dd	_unloop, _drop, _e

COLON	"preprocess", preprocess
	dd	_string_for, _two_to_r, _branch, .test
.loop:	dd	_r_fetch, _c_fetch, _bl, _less
	dd	_0branch, .next, _bl, _r_fetch, _c_store
.next:	dd	_loop_inc
.test:	dd	_loop_test, .loop
	dd	_unloop, _e

; Word parsing

COLON	"input-position", input_position
	dd	_tib, _fetch, _to_in, _fetch, _plus, _e


COLON	"parse-delimited", parse_delimited
	dd	_dup, _parse_skip, _parse, _e

COLON	"parse", parse
	dd	_input_position, _swap, _parse_until, _input_position
	dd	_over, _minus, _to_in, _one_plus_store, _e

COLON	"parse-name", parse_name
	dd	_bl, _parse_delimited, _e

COLON	"word", word
	dd	_parse_delimited, _prepare_word, _e

CONSTANT	"bl", bl, 32

; Outer interpreter

COLON	"interpret", interpret
	dd	_source, _preprocess
.loop:	dd	_bl, _word, _dup, _c_fetch, _0branch, .empty
	dd	_find
	dd	_l, 1, _of, @f, _execute, _branch, .loop
@@:	dd	_l, -1, _of, @f
	dd		_state, _fetch, _0branch, .a
	dd			_comma, _branch, .loop
.a:	dd		_execute, _branch, .loop
@@:	dd	_drop, _count, _str_to_num, _0branch, .notfound
	dd		_state, _fetch, _0branch, .loop
	dd		_literal, _branch, .loop
.notfound:
	dd	_l, -13, _bye
.empty:	dd	_drop, _e

; Default input source

COLON	"refill", refill
	dd	_l, input_buffer, _tib, _store
	dd	_l, input_buffer, _l, 128, _accept
	dd	_dup, _l, 1, _less, _0branch, @f, _bye
@@:	dd	_ntib, _store, _l, 0, _to_in, _store
	dd	_l, 1, _e

COLON	"quit", quit
.loop:	dd	_refill, _drop, _interpret, _branch, .loop

; Creating words

COLON	"create-header", create_header
	dd	_align, _latest, _here, _store
	dd	_here, _dup, _dt_xt, _data_pointer, _store, _e

COLON	"create-codefield", create_codefield
	dd	_comma, _l, 0, _comma, _e

COLON	"[", left_bracket, 1
	dd	_l, 0, _state, _store, _e

COLON	"]", right_bracket
	dd	_l, 1, _state, _store, _e

COLON	":", colon
	dd	_bl, _word, _drop, _create_header
	dd	_l, code_docolon, _create_codefield
	dd	_right_bracket, _e

COLON	";", semicolon, 1
	dd	_dict, _store, _left_bracket, _l, _e, _comma, _e

COLON	"create-word", create_word
	dd	_bl, _word, _drop, _create_header
	dd	_swap, _create_codefield
	dd	_dict, _store, _e

COLON	"constant", constant
	dd	_l, code_doconst, _create_word, _comma, _e

COLON	"create", create
	dd	_l, code_dovar, _create_word, _e

COLON	"variable", variable
	dd	_create, _l, 0, _comma, _e

COLON	"alias", alias
	dd	_l, code_dodefer, _create_word, _comma, _e

; Interpreter variables

input_buffer:
	db	128 dup 0xa5

VARIABLE	"dictionary", dict, dictionary_end
VARIABLE	"tib", tib, 0
VARIABLE	"#tib", ntib, 0
VARIABLE	">in", to_in, 0
VARIABLE	"state", state, 0
VARIABLE	"data-pointer", data_pointer, 0
VARIABLE	"base", base, 10
