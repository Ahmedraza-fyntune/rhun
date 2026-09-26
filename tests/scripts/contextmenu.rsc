# right click keeps the selection; menu Copy, then paste elsewhere
open tests/data/words.txt
click 312 87
click 312 87
click 316 90 right
click 356 150
cmd new_file
key ctrl+v
print-doc
quit
