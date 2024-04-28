variable actual-depth
create results 32 cells allot
variable start-depth

: t{ initial-sp sp! ;

: ->
	depth dup actual-depth !
	0 ?do results i cells + ! loop ;

: }t
	depth actual-depth @ <> if abort" stack length mismatch" then
	depth 0 ?do
		results i cells + @ <> if abort" wrong result" then
	loop f} ;
