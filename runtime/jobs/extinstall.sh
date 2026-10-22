# Installing an extension (src/app/extinstall.s; remote windows fetch a host's build with it too,
# src/app/remoteext.s), after runtime/jobs/archive.sh: OWNER NAME TARGET ROOT BASE TAG WANT FILE
# KIND as $1..$9 (github: a TAG or "latest", the index's digest or "-"; archive and folder: the
# FILE). The last line is "ok SHA256 TAG DIR", or why it failed.
set -u
owner=$1 name=$2 target=$3 root=$4 base=$5 tag=$6 want=$7 file=$8 kind=$9
export COPYFILE_DISABLE=1
mkdir -p "$root" || { echo "cannot create $root"; exit 1; }
tmp=$(mktemp -d "$root/.install-XXXXXX") || { echo "cannot create a folder in $root"; exit 1; }
fail() { rm -rf "$tmp"; echo "$1"; exit 1; }
fetch_init "$base"
sums() { awk -v f="$2" '$2 == f || $2 == "*" f { print $1 }' "$1"; }
what=archive wantsum=
case $kind in
github)
  if [ "$tag" = latest ]; then
    case $base in
    file:*) url=$base/$owner/$name/releases/latest/download ;;
    *) loc=$(where "$base/$owner/$name/releases/latest") || fail "no answer from $base"
      case $loc in */releases/tag/*) tag=${loc##*/releases/tag/} ;; *) fail "$owner/$name has no release" ;; esac
      case $tag in ''|*[!0-9A-Za-z._-]*) fail "the latest release has an unusable tag" ;; esac
      url=$base/$owner/$name/releases/download/$tag ;;
    esac
  else url=$base/$owner/$name/releases/download/$tag; fi
  asset=$name-$target.tar.gz
  get "$url/$asset" "$tmp/a.tgz" || { [ "$tag" = latest ] && fail "no release of $owner/$name for $target"; fail "no release $tag of $owner/$name for $target"; }
  get "$url/sha256sums.txt" "$tmp/sums" || fail "the release has no sha256sums.txt"
  wantsum=$(sums "$tmp/sums" "$asset")
  [ -n "$wantsum" ] || fail "the release's sha256sums.txt does not list $asset" ;;
archive)
  asset=${file##*/}
  cp "$file" "$tmp/a.tgz" 2>/dev/null || fail "cannot read $file"
  if [ -f "${file%/*}/sha256sums.txt" ]; then
    wantsum=$(sums "${file%/*}/sha256sums.txt" "$asset")
    [ -n "$wantsum" ] || fail "the sha256sums.txt beside it does not list $asset"
  fi ;;
folder)
  what=folder
  [ -f "$file/extension.ini" ] || fail "the folder has no extension.ini"
  tar -czf "$tmp/a.tgz" -C "$file" . 2>/dev/null || fail "the folder cannot be read" ;;
*) fail "unknown source" ;;
esac
if command -v sha256sum >/dev/null 2>&1; then have=$(sha256sum "$tmp/a.tgz"); else have=$(shasum -a 256 "$tmp/a.tgz"); fi
have=${have%% *}
[ -z "$wantsum" ] || [ "$wantsum" = "$have" ] || fail "the download does not match its checksum"
[ "$want" = - ] || [ "$want" = "$have" ] || fail "the download is not the version the rhun extensions index reviewed"
unpack "$tmp/a.tgz" "$tmp/x"
[ -f "$tmp/x/extension.ini" ] || fail "the $what has no extension.ini"
rm -f "$tmp/a.tgz" "$tmp/sums"
echo "ok $have $tag $tmp"
