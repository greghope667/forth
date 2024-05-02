sp@ constant initial-sp
: depth sp@ initial-sp swap - 3 rshift ;
: clear-stack initial-sp sp! ;
: .s depth 0 ?do depth 1- i - pick . loop ;
