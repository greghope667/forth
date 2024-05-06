: immediate 1 latest dt>flags c! ;
: postpone ' , ; immediate
: ['] ' postpone literal ; immediate
: char bl word 1+ c@ ;
: [char] char postpone literal ; immediate
: ( [char] ) parse 2drop ; immediate
: .( [char] ) parse type ; immediate
: \ #tib @ >in ! ; immediate
