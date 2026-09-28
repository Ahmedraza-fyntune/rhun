# source control in a repository without commits (tests/data/gitinit.setup): the work tree row alone,
# Enter on it goes to the message, Ctrl+Enter makes the first commit
open @HOME@/repo
wait-git
cmd git_history
wait-git
print-gitlog
print-scm
key Return
print-state
type First
key ctrl+Return
wait-git
print-git
print-gitlog
print-scm
