# Open Folder and the project menu: the window takes up another folder, asking about unsaved files
# first; each folder comes back with its last session. The menu lists the recent folders.
open @HOME@/work/alpha
open @HOME@/work/alpha/a.txt
type x
cmd open_folder
print-palette
type ../
print-palette
type b
print-palette
key Return
print-palette
key Return
print-state
key Escape
print-project
print-state
# the menu: the latest sessions' folders, but not this one or one that is gone; Esc closes it
click 60 20
print-menu
key Escape
print-menu
click 60 20
click 100 166
print-state
key Return
print-project
print-state
click 60 20
print-menu
click 100 134
print-project
print-state
print-doc
# Ctrl+Enter opens the selected folder instead of going into it
cmd open_folder
key BackSpace
key BackSpace
key BackSpace
key BackSpace
key BackSpace
key BackSpace
type ga
key ctrl+Return
print-project
print-state
quit
