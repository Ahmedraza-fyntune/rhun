# right click keeps the selection; menu Copy, then paste elsewhere
open tests/data/words.txt
click 330 87
click 330 87
click 340 90 right
click 380 150
cmd new_file
key ctrl+v
print-doc
quit
