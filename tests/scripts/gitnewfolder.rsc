# git: a new folder's files each get a row in the Git panel (git ls-files --others), and a click shows
# that file's changes; the folder's ignored file stays out (tests/data/gitnewfolder.setup)
# start: @HOME@/repo
wait-git
cmd git_history
wait-git
# the folder's row until its files are known
print-scm
wait-git
print-scm
# the history counts the files the panel lists
print-gitlog
click 800 342
wait-git
print-state
print-doc
cmd git_history
click 800 314
wait-git
print-state
print-doc
quit
