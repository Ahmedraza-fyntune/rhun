# click, double click word, triple click line, drag selection, a click after a partial-line scroll
# (x includes the gutter's fold lane)
open tests/data/words.txt
click 324 87
print-state
click 324 87
click 324 87
print-state
click 324 87
print-state
move 317 108
down
move 432 129
up
print-state
type X
print-doc
# a click after scrolling part of a line lands on the line under the pointer
open tests/data/lines.c
scroll 40
click 412 300
print-state
wait 500
scroll 57
click 412 300
print-state
quit
