# Downloading and unpacking for rhun's background jobs: tools/gen-assets.sh puts this before
# runtime/jobs/extinstall.sh (install_script) and runtime/jobs/newext.sh (newext_script). The job
# defines fail MESSAGE (it exits), sets what (the word its messages use for the archive) and calls
# fetch_init BASE before the first get.
# fetch_init BASE: curl when there is one, else wget; an https BASE stays https through redirects
fetch_init() {
  proto=; case $1 in https:*) proto='--proto =https --proto-redir =https' ;; esac
  curl=; command -v curl >/dev/null 2>&1 && curl=1
}
# get URL FILE: at most 64 MB, two minutes
get() {
  if [ -n "$curl" ]; then curl -fsSL $proto --max-time 120 --max-filesize 67108864 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -T 120 -O "$2" "$1"
  else fail "neither curl nor wget is installed"; fi
}
# where URL: where it redirects to
where() {
  if [ -n "$curl" ]; then curl -fsS $proto -o /dev/null --max-time 20 -w '%{redirect_url}' "$1"
  else wget -S --max-redirect=0 -T 20 -O /dev/null "$1" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tr -d '\r' | head -n 1; fi
}
# unpack ARCHIVE DEST: a .tar.gz of plain files and folders only (no links or devices), nothing
# outside itself, at most 64 MB unpacked, into the new folder DEST
unpack() {
  tar -tvzf "$1" > "$1.list" 2>/dev/null || fail "the $what cannot be read"
  grep -q '^[^-d]' "$1.list" && fail "the $what holds links or devices"
  tar -tzf "$1" | grep -Eq '(^/|(^|/)[.][.](/|$))' && fail "the $what reaches outside itself"
  size=$(awk '{ s += ($2 ~ /\//) ? $3 : $5 } END { printf "%.0f", s }' "$1.list")
  rm -f "$1.list"
  [ "$size" -le 67108864 ] 2>/dev/null || fail "the $what unpacks to more than 64 MB"
  mkdir "$2" && tar -xzf "$1" -C "$2" 2>/dev/null || fail "the $what cannot be unpacked"
}
