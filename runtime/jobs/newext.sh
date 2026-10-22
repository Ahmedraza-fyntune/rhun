# A new extension (rhun new-extension and Extensions: New Extension..., src/app/newext.s), after
# runtime/jobs/archive.sh: NAME OWNER LANG (rust or go) SKILLS (yes or no) DIR BASE UI (cli or gui)
# as $1..$7. The template's main branch comes from BASE/rhun-editor/template-LANG/tar.gz/refs/heads/
# main (codeload.github.com, or RHUN_NEW_EXT_BASE), is checked and unpacked as an extension
# archive is, renamed to OWNER/NAME, and with SKILLS the skills repository's rhun-extension skill
# goes into .claude/skills (Claude Code) and .agents/skills (Codex). It is put together in a
# folder beside DIR and moved into place last, then git init. With UI cli it reports to the
# terminal; with gui the lines are "tmp PATH", "step N M TEXT", then "ok DIR" or "fail WHY".
set -u
name=$1 owner=$2 lang=$3 skills=$4 dir=$5 base=$6 ui=$7
export COPYFILE_DISABLE=1
tmp=
fail() {
  [ -z "$tmp" ] || rm -rf "$tmp"
  if [ "$ui" = gui ]; then echo "fail $1"; else echo "rhun new-extension: $1" >&2; fi
  exit 1
}
trap '[ -z "$tmp" ] || rm -rf "$tmp"; exit 130' INT TERM HUP
step() { if [ "$ui" = gui ]; then echo "step $1 $total $2"; else echo "$2"; fi; }
# only FOLDER: the one entry in FOLDER, a folder (a GitHub archive's top folder)
only() {
  n=0
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$f" ] || continue
    n=$((n + 1)); one=$f
  done
  [ "$n" = 1 ] && [ -d "$one" ] && echo "$one"
}
case $lang in rust) Lang=Rust ;; go) Lang=Go ;; *) fail "the language is rust or go, not $lang" ;; esac
case $name in ''|-*|*[!a-z0-9-]*) fail "the name is lowercase letters, digits and dashes: $name" ;; esac
[ "$lang" != rust ] || case $name in [0-9]*) fail "a Rust package name starts with a letter: $name" ;; esac
case $owner in ''|-*|*[!A-Za-z0-9-]*) fail "the owner is a GitHub user or organization: $owner" ;; esac
case $dir in /*) ;; *) dir=$PWD/$dir ;; esac
if [ -e "$dir" ] || [ -L "$dir" ]; then
  { [ -d "$dir" ] && [ ! -L "$dir" ]; } || fail "$dir is there and is not a folder"
  [ -z "$(ls -A "$dir" 2>/dev/null)" ] || fail "$dir is not empty"
fi
parent=$(dirname "$dir")
mkdir -p "$parent" 2>/dev/null || fail "cannot create $parent"
tmp=$(mktemp -d "$parent/.rhun-new-XXXXXX" 2>/dev/null) || { tmp=; fail "cannot create a folder in $parent"; }
[ "$ui" != gui ] || echo "tmp $tmp"
total=3
[ "$skills" != yes ] || total=4
fetch_init "$base"

what=template
step 1 "Downloading the $Lang template"
url=$base/rhun-editor/template-$lang/tar.gz/refs/heads/main
get "$url" "$tmp/t.tgz" || fail "could not download the $Lang template ($url)"
unpack "$tmp/t.tgz" "$tmp/t"
rm -f "$tmp/t.tgz"
src=$(only "$tmp/t") || fail "the template archive does not hold one folder"
[ -f "$src/extension.ini" ] || fail "the template has no extension.ini"

step 2 "Naming it $owner/$name"
ini() { sed -n "s/^$1 *= *//p" "$src/extension.ini" | head -n 1 | tr -d '\r'; }
old=$(ini name)
oldowner=$(ini owner)
case $old in ''|-*|*[!a-z0-9-]*) fail "the template's manifest has no usable name" ;; esac
case $oldowner in ''|-*|*[!A-Za-z0-9-]*) fail "the template's manifest has no usable owner" ;; esac
title=$(echo "$name" | awk -F- '{ s = ""; for (i = 1; i <= NF; i++) if ($i != "") s = s (s == "" ? "" : " ") toupper(substr($i, 1, 1)) substr($i, 2); print s }')
# edit FILE SED-SCRIPT: in place, keeping the file's mode (tests/run.sh stays executable)
edit() {
  [ -f "$src/$1" ] || return 0
  sed -e "$2" "$src/$1" > "$tmp/edit" && cat "$tmp/edit" > "$src/$1" || fail "cannot change $1"
}
# the manifest: name, owner, title, and the programs named after the extension
edit extension.ini "s|^name *=.*|name = $name|;s|^owner *=.*|owner = $owner|;s|^title *=.*|title = $title|;s|^\(run[.a-z0-9_-]* *=.*/\)$old\([.-]\)|\1$name\2|"
# Go: the module; Rust: the package (the program cargo builds)
edit go.mod "s|^module .*|module github.com/$owner/$name|"
edit Cargo.toml "s|^name = \"$old\"|name = \"$name\"|"
edit Cargo.lock "s|^name = \"$old\"|name = \"$name\"|"
# the headless test's script, its expected output and the scripts that read them: OWNER/NAME
# and the commands NAME.COMMAND
for f in "$src"/tests/*; do
  [ -f "$f" ] || continue
  edit "tests/${f##*/}" "s|$oldowner/$old|$owner/$name|g;s|$oldowner\\\\/$old|$owner\\\\/$name|g;s|\([ =,]\)$old\.|\1$name.|g;s|^wait-ext $old |wait-ext $name |;s|^ext=$old |ext=$name |"
done
edit README.md "1s|^# .*|# $title|"

if [ "$skills" = yes ]; then
  what="skills archive"
  step 3 "Adding the agent skills"
  url=$base/rhun-editor/skills/tar.gz/refs/heads/main
  get "$url" "$tmp/s.tgz" || fail "could not download the agent skills ($url)"
  unpack "$tmp/s.tgz" "$tmp/s"
  rm -f "$tmp/s.tgz"
  sk=$(only "$tmp/s") || fail "the skills archive does not hold one folder"
  sk=$sk/plugins/rhun/skills/rhun-extension
  [ -f "$sk/SKILL.md" ] || fail "the skills archive has no plugins/rhun/skills/rhun-extension"
  # Claude Code reads .claude/skills, Codex .agents/skills (and .codex/skills), from the project
  for d in .claude/skills .agents/skills; do
    rm -rf "$src/$d/rhun-extension"
    mkdir -p "$src/$d" && cp -R "$sk" "$src/$d/" || fail "cannot copy the skills to $d"
  done
  if [ ! -f "$src/AGENTS.md" ]; then
    printf '# Working on this rhun extension\n\nThis is an extension for the rhun editor. Read the rhun-extension skill first:\n`.agents/skills/rhun-extension/SKILL.md` (the same skill as `.claude/skills/rhun-extension`).\nThe protocol: https://rhun.app/extensions/v1/\n' > "$src/AGENTS.md" || fail "cannot write AGENTS.md"
  fi
  [ -f "$src/CLAUDE.md" ] || echo "@AGENTS.md" > "$src/CLAUDE.md"
fi

step "$total" "Creating $dir"
[ ! -d "$dir" ] || rmdir "$dir" 2>/dev/null || fail "cannot replace the empty folder $dir"
mv "$src" "$dir" 2>/dev/null || fail "cannot create $dir"
rm -rf "$tmp"
tmp=
if command -v git >/dev/null 2>&1; then git init -q "$dir" >/dev/null 2>&1 || echo "git init did not work in $dir" >&2; fi
if [ "$ui" = gui ]; then echo "ok $dir"; exit 0; fi
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=linux-x86_64 ;;
  Darwin-arm64) target=macos-arm64 ;;
  *) target=TARGET ;;
esac
echo
echo "Created $owner/$name ($Lang) in $dir"
echo
echo "Next:"
echo "  cd $dir"
if [ "$lang" = go ]; then
  echo "  go build -o bin/$name-$target .        # the program extension.ini runs"
else
  echo "  cargo build --release && mkdir -p bin && cp target/release/$name bin/$name-$target"
fi
echo "  sh tests/run.sh                  # the headless test (rhun on PATH)"
echo "  then in rhun: Link Extension Folder (development) with $dir, and Restart after each build"
