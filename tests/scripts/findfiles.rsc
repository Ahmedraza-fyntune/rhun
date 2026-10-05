# find in files opens at once and reads the project's files after its first frame: keys work while
# it reads, and once every file is read the query runs over all of them
# start: tests/data/findfiles
key ctrl+shift+f
print-palette
type quokka
print-palette
wait-grep
print-palette
key Down
key Return
print-state
quit
