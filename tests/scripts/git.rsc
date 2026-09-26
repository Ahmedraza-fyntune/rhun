# git: status of the work tree, change marks of open files, refresh after a commit
open @HOME@/repo
wait-git
print-git
open @HOME@/repo/a.txt
wait-git
print-git
key ctrl+End
key Return
type eight
print-git
key ctrl+z
key ctrl+z
print-git
key ctrl+Home
key ctrl+shift+k
print-git
open @HOME@/repo/crlf.txt
wait-git
print-git
cmd toggle_terminal
wait 300
type git commit -qam 'Commit all'
key Return
wait 1500
wait-git
print-git
cmd prev_tab
print-git
cmd open_config
key ctrl+End
key Return
type [git]
key Return
type enabled = false
key Return
key ctrl+s
wait-git
print-git
