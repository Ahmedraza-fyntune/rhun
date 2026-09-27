# Open File: a browser from the project folder. Enter goes into a folder, Backspace past a / goes up,
# hidden entries need a leading dot, Tab takes a name; a file outside the project opens in a tab
open @HOME@/work/alpha
cmd open_file
print-palette
type s
print-palette
key Return
print-palette
key Return
print-state
cmd open_file
type .
print-palette
key BackSpace
key BackSpace
print-palette
key ctrl+a
type ~/no
print-palette
key Tab
print-palette
key Return
print-state
print-project
# from the project menu
click 60 20
print-menu
click 100 94
print-palette
key Escape
print-palette
quit
