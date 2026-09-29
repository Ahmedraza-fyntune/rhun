# click, double click word, triple click line, drag selection, a click after a partial-line scroll
open tests/data/words.txt
click 312 87
print-state
click 312 87
click 312 87
print-state
click 312 87
print-state
move 305 108
down
move 420 129
up
print-state
type X
print-doc
# a click after scrolling part of a line lands on the line under the pointer
open tests/data/lines.c
scroll 40
click 400 300
print-state
wait 500
scroll 57
click 400 300
print-state
quit
