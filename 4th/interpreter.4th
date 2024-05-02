\ Core words to run bootstrapping forth code
\ These are hand-translated to assembler directives

: count dup 1+ swap c@ ;
: /string tuck - >r + r> ;

: align here aligned data-pointer ! ;
: 2align here 2aligned data-pointer ! ;

\ type dt dictionary/name token

: dt>next ( dt -- dt | 0 ) @ ;
: dt>name ( dt -- c-addr ) 5 + ;
: dt>xt ( dt -- xt ) dt>name dup c@ + 1+ 2aligned ;
: dt-immediate? ( dt -- f ) 4 + c@ 1 and ;
: dt<> ( caddr dt -- f ) dt>name dup c@ 1+ memcompare 0<> ;

variable dictionary

: latest dictionary @ ;

: lookup ( caddr -- dt | 0 )
	latest
	begin
		dup while
		2dup dt<> while
		dt>next
	repeat then nip ;

: lookup-buffer here aligned dt>name ;

: prepare-word ( caddr u -- caddr )
	lookup-buffer >r
	30 min
	dup r@ c!
	r@ 1+ swap move r> ;

variable tib
variable #tib
variable >in

: source ( -- addr u ) tib @ #tib @ ;
: parse-area ( -- caddr u ) source >in @ /string ;
: string-for ( caddr u -- end begin ) over + swap ;

: parse-skip ( c -- )
	parse-area string-for ?do
		dup i c@ = ?leave
		>in 1+!
	loop drop ;

: parse-until ( c -- )
	parse-area string-for ?do
		dup i c@ <> ?leave
		>in 1+!
	loop drop ;

: preprocess ( caddr u -- )
	string-for ?do
		i c@ bl < if bl i c! then
	loop ;

create input-buffer 128 chars allot
input-buffer tib !

: refill
	input-buffer 128 accept
	dup 1 < if 1 bye then
	#tib ! 0 >in !
	true ;

: input-position ( -- caddr )
	>in @ tib @ + ;

: parse ( char "ccc<char>" -- caddr u)
	input-position swap parse-until input-position
	over - >in 1+! ;

: parse-delimited ( char "" -- caddr u )
	dup parse-skip parse ;

32 constant bl

: parse-name bl parse-delimited ;

: word parse-delimited prepare-word ;

: find
	dup lookup \ caddr dt
	dup if
		nip \ dt
		dup	dt>xt swap \ xt dt
		dt-immediate? 2* 1- \ xt 1|0
	then ;

: interpret
	source preprocess
	begin
		bl word dup c@ while find case
			1 of execute endof
			-1 of state @ if , else execute then endof
			drop count str>num if
				state @ if postpone literal then
			else
				-13 throw
			then
		dup endcase
	repeat drop ;

: literal ['] (lit) , , ; immediate

variable data-pointer
: here data-pointer @ ;
: , here ! 4 data-pointer + ;

: quit begin refill drop interpret again ;

: create-header ( -- dt )
	align latest here !
	here dup dt>xt data-pointer ! ;

: create-codefield ( codefield -- ) , 0 , ;

: [ 0 state ! ; immediate
: ] 1 state ! ;

: : bl word drop create-header _code_docolon create-codefield ] ;
: ; dictionary ! ['] exit , postpone [ ;

: create-word ( codefield -- )
	bl word drop create-header swap , 0 , dictionary ! ;

: constant _code_doconst create-word , ;
: create _code_dovar create-word ;
: variable create 0 , ;
: alias _code_dodefer create-word , ;

: ' bl word find 0= if -13 throw then ;
