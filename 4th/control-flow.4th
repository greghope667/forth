: prepare> ( -- fwd ) here 0 , ;
: resolve> ( fwd -- ) here swap ! ;
: <prepare ( -- rev ) here ;
: <resolve ( rev -- ) , ;

: if ['] 0branch , prepare> ; immediate
: else ['] branch , prepare> swap resolve> ; immediate
: then resolve> ; immediate

: begin <prepare ; immediate
: again ['] branch , <resolve ; immediate
: while postpone if swap ; immediate
: repeat postpone again postpone then ; immediate

variable leave-list

: ?do ['] 2>r , ['] branch , prepare> <prepare 0 leave-list ! ; immediate
: leave ['] branch , here leave-list @! , ; immediate
( code : unloop 2>r 2drop ; )
: loop
	['] (loopi) , swap resolve> ( branch ?do -> test )
	['] (?loop) , <resolve ( branch test -> start )
	leave-list begin
		?dup while
		dup @ swap resolve>
	repeat
	['] unloop ,
	; immediate
' r@ alias i
