# Submitting an extension's release to the rhun extensions index, github.com/rhun-editor/extensions
# (rhun submit-extension and Extensions: Submit to Index..., src/app/submitext.s), after
# runtime/jobs/archive.sh. Two steps; every line it prints is for rhun to read:
#   prepare DIR TAG GITHUB API RAW: DIR/extension.ini's owner, name and version (TAG "-": vVERSION),
#     the release's sha256sums.txt (GITHUB/OWNER/NAME/releases/download/TAG), the tag's commit
#     (API/repos/OWNER/NAME/commits/TAG), the index's entry if there is one (RAW/rhun-editor/
#     extensions/main/OWNER/NAME.ini) and whether gh is logged in. Lines: "work PATH" (a folder the
#     submit step takes), "step N M TEXT", "full OWNER/NAME", "tag TAG", "existing yes|no", then the
#     entry's "category C", "keywords K", "maintainer M" when it has them, "gh LOGIN" or "gh -",
#     "warn TEXT", and last "ok" or "fail WHY".
#   submit WORK CATEGORY KEYWORDS MAINTAINER HOW: the entry, written as the index's files are
#     (WORK/entry.ini, "say LINE" for each line), then with HOW gh a fork, a branch and a pull
#     request through gh ("pr URL"), or with HOW browser GitHub's page that proposes the file
#     ("url URL"); last "ok" or "fail WHY". WORK goes either way.
set -u
work=
fail() { [ -z "$work" ] || rm -rf "$work"; echo "fail $1"; exit 1; }
step() { echo "step $1 $2 $3"; }
mode=$1
shift
case $mode in
prepare)
  dir=$1 tag=$2 github=$3 api=$4 raw=$5
  ini=$dir/extension.ini
  [ -f "$ini" ] || fail "$dir has no extension.ini"
  key() { sed -n "s/^$1 *= *//p" "$ini" | head -n 1 | tr -d '\r'; }
  owner=$(key owner)
  name=$(key name)
  version=$(key version)
  case $owner in ''|.*|*[!A-Za-z0-9._-]*) fail "extension.ini has no usable owner" ;; esac
  case $name in ''|.*|*[!A-Za-z0-9._-]*) fail "extension.ini has no usable name" ;; esac
  if [ "$tag" = - ]; then
    [ -n "$version" ] || fail "extension.ini has no version"
    tag=v$version
  fi
  case $tag in ''|*[!0-9A-Za-z._-]*) fail "$tag is not a release tag" ;; esac
  full=$owner/$name
  work=$(mktemp -d "${TMPDIR:-/tmp}/rhun-submit-XXXXXX") || { work=; fail "cannot create a temporary folder"; }
  echo "work $work"
  echo "$full" > "$work/full"
  echo "$tag" > "$work/tag"
  step 1 3 "Reading the release $tag of $full"
  rel=$github/$full/releases/download/$tag
  fetch_init "$github"
  get "$rel/sha256sums.txt" "$work/sums" 2>/dev/null || fail "$full has no release $tag with a sha256sums.txt ($rel/sha256sums.txt)"
  # NAME-TARGET.tar.gz lines, by target
  awk -v p="$name-" '{
    f = $2; sub(/^\*/, "", f)
    if (index(f, p) != 1 || substr(f, length(f) - 6) != ".tar.gz") next
    t = substr(f, length(p) + 1); t = substr(t, 1, length(t) - 7)
    if (t == "" || t ~ /[^a-z0-9_-]/ || length($1) != 64 || $1 ~ /[^0-9a-f]/) next
    print t, $1
  }' "$work/sums" | LC_ALL=C sort > "$work/targets"
  [ -s "$work/targets" ] || fail "the release's sha256sums.txt lists no $name-TARGET.tar.gz"
  step 2 3 "Reading the commit of $tag"
  url=$api/repos/$full/commits/$tag
  fetch_init "$api"
  get "$url" "$work/commit.json" 2>/dev/null || fail "could not read the commit of $tag ($url)"
  commit=$(tr -d '\r\n' < "$work/commit.json" | sed -n 's/^[^"]*"sha" *: *"\([0-9a-f]\{40\}\)".*/\1/p')
  [ -n "$commit" ] || fail "the answer for the commit of $tag has no sha ($url)"
  {
    echo "tag = $tag"
    echo "commit = $commit"
    while read -r t d; do echo "sha256.$t = $d"; done < "$work/targets"
  } > "$work/pins"
  echo "full $full"
  echo "tag $tag"
  step 3 3 "Looking for $full in the index"
  fetch_init "$raw"
  if get "$raw/rhun-editor/extensions/main/$full.ini" "$work/old" 2>/dev/null && grep -q '^tag *=' "$work/old"; then
    echo "existing yes"
    for k in category keywords maintainer; do
      v=$(sed -n "s/^$k *= *//p" "$work/old" | head -n 1 | tr -d '\r')
      [ -z "$v" ] || echo "$k $v"
    done
  else
    rm -f "$work/old"
    echo "existing no"
  fi
  # the index's check verifies the archives' attestation against this workflow
  wf=$dir/.github/workflows/release.yml
  grep -q 'actions/attest-build-provenance' "$wf" 2>/dev/null ||
    echo "warn .github/workflows/release.yml does not attest the archives (actions/attest-build-provenance): the index's check needs that attestation, so add it (as the templates have it) and release again"
  login=-
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    login=$(gh api user --jq .login 2>/dev/null | tr -d '\r')
    case $login in ''|-*|*[!A-Za-z0-9-]*) login=- ;; esac
  fi
  echo "gh $login"
  echo ok ;;
submit)
  work=$1 category=$2 keywords=$3 maintainer=$4 how=$5
  case $work in */rhun-submit-*) ;; *) work=; fail "no prepared submission" ;; esac
  [ -f "$work/pins" ] || fail "no prepared submission"
  full=$(cat "$work/full")
  tag=$(cat "$work/tag")
  case " languages formatters themes testing debugging tools packs other " in
    *" $category "*) ;; *) fail "the category is one of languages formatters themes testing debugging tools packs other" ;;
  esac
  case $keywords in *[!a-z0-9\ ._+#-]*) fail "keywords are lowercase words" ;; esac
  case $maintainer in ''|-*|*[!A-Za-z0-9-]*) fail "the maintainer is a GitHub user" ;; esac
  # the entry, as the index's files are written; what only the index's maintainers set stays
  {
    echo "# rhun-editor/extensions: $full.ini"
    echo "category = $category"
    [ -z "$keywords" ] || echo "keywords = $keywords"
    echo "maintainer = $maintainer"
    if [ -f "$work/old" ]; then
      for k in featured rhun; do
        v=$(sed -n "s/^$k *= *//p" "$work/old" | head -n 1 | tr -d '\r')
        case $v in ''|*[!0-9A-Za-z._-]*) ;; *) echo "$k = $v" ;; esac
      done
    fi
    echo "# the reviewed release; a new version is a new pull request"
    cat "$work/pins"
  } > "$work/entry.ini"
  while IFS= read -r line; do echo "say $line"; done < "$work/entry.ini"
  case $how in
  gh)
    login=$(gh api user --jq .login 2>&1 | tr -d '\r') || fail "gh is not logged in: $login"
    case $login in ''|-*|*[!A-Za-z0-9-]*) fail "gh did not say who is logged in" ;; esac
    step 1 4 "Forking rhun-editor/extensions as $login/extensions"
    if parent=$(gh api "repos/$login/extensions" --jq .parent.full_name 2>/dev/null); then
      parent=$(echo "$parent" | tr -d '\r')
      [ "$parent" = rhun-editor/extensions ] || fail "$login/extensions is there and is not a fork of rhun-editor/extensions"
    else
      out=$(gh repo fork rhun-editor/extensions --clone=false --default-branch-only 2>&1) || fail "gh could not fork rhun-editor/extensions: $out"
    fi
    branch=submit-$(echo "$full" | tr / -)-$tag
    step 2 4 "Making the branch $branch"
    gh api -X POST "repos/$login/extensions/merge-upstream" -f branch=main >/dev/null 2>&1 || true
    # a new fork takes a moment to have its main
    i=0
    while :; do
      sha=$(gh api "repos/$login/extensions/git/ref/heads/main" --jq .object.sha 2>/dev/null | tr -d '\r') && [ -n "$sha" ] && break
      i=$((i + 1))
      [ "$i" -lt 10 ] || fail "the fork $login/extensions has no main branch yet; try again in a minute"
      sleep 3
    done
    out=$(gh api -X POST "repos/$login/extensions/git/refs" -f "ref=refs/heads/$branch" -f "sha=$sha" 2>&1) ||
      case $out in *"already exists"*) ;; *) fail "gh could not make the branch $branch: $out" ;; esac
    step 3 4 "Putting $full.ini on it"
    old=$(gh api "repos/$login/extensions/contents/$full.ini?ref=$branch" --jq .sha 2>/dev/null | tr -d '\r') || old=
    content=$(base64 < "$work/entry.ini" | tr -d '\r\n')
    set -- -X PUT "repos/$login/extensions/contents/$full.ini" -f "message=$full $tag" -f "content=$content" -f "branch=$branch"
    [ -z "$old" ] || set -- "$@" -f "sha=$old"
    out=$(gh api "$@" 2>&1) || fail "gh could not put $full.ini on $branch: $out"
    step 4 4 "Opening the pull request"
    commit=$(sed -n 's/^commit = //p' "$work/pins")
    body="Release: https://github.com/$full/releases/tag/$tag

The index's checks (.github/workflows/check.yml) run on it:
- \`go run ./tools/genindex -check\`: the pinned digests against the release's sha256sums.txt, one archive downloaded and its manifest's owner, name and version, the 64 MB limit, no links or devices
- \`rhun-ext-check\` on the Linux build
- \`gh attestation verify\` of the archive against commit $commit and $full's .github/workflows/release.yml
- a review of the source since the previously pinned commit

Made by rhun submit-extension."
    out=$(gh pr create -R rhun-editor/extensions --base main --head "$login:$branch" --title "$full $tag" --body "$body" 2>&1) ||
      fail "gh could not open the pull request: $out"
    url=$(printf '%s\n' "$out" | grep -o 'https://[^ ]*/pull/[0-9]*' | tail -n 1)
    echo "pr ${url:-$out}" ;;
  browser)
    if [ -f "$work/old" ]; then
      # the file is there: GitHub's editor for it (the entry above replaces its text)
      echo "edit yes"
      echo "url https://github.com/rhun-editor/extensions/edit/main/$full.ini"
    else
      value=$(od -An -v -tx1 < "$work/entry.ini" | awk '
        BEGIN { for (i = 48; i < 58; i++) ok[sprintf("%02x", i)] = sprintf("%c", i)
                for (i = 65; i < 91; i++) ok[sprintf("%02x", i)] = sprintf("%c", i)
                for (i = 97; i < 123; i++) ok[sprintf("%02x", i)] = sprintf("%c", i)
                ok["2d"] = "-"; ok["2e"] = "."; ok["5f"] = "_"; ok["7e"] = "~" }
        { for (i = 1; i <= NF; i++) printf "%s", ($i in ok) ? ok[$i] : "%" toupper($i) }')
      echo "url https://github.com/rhun-editor/extensions/new/main?filename=$full.ini&value=$value"
    fi ;;
  *) fail "submit with gh or the browser" ;;
  esac
  rm -rf "$work"
  work=
  echo ok ;;
*) fail "unknown step $mode" ;;
esac
