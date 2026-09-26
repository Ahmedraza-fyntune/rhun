# closing tabs from the strip: middle click, then the last one with its close button
cmd settings
open tests/data/words.txt
open README.md
click 280 58 middle
print-state
click 280 58 middle
print-state
click 333 58
print-state
cmd new_file
print-state
quit
