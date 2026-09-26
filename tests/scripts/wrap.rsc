# soft wrap: rows, vertical motion by row, clicks and selection on wrapped rows
open tests/data/prose.md
cmd toggle_word_wrap
key Down
key Down
key Down
print-state
key Down
key Down
print-state
click 500 150
print-state
key shift+Down
key shift+Down
print-state
key Escape
click 700 380
print-state
type Q
print-state
key ctrl+z
key ctrl+End
key Up
key Up
print-state
key ctrl+Home
key PageDown
print-state
cmd toggle_word_wrap
key Down
print-state
quit
