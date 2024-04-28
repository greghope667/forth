: . here num>str type ;
: emit sp@ 1 type drop ;
: book latest begin ?dup while dup dt>name count type dt>next bl emit repeat ;
: decimal 10 base ! ;
: hex 16 base ! ;
