#!/usr/bin/env bash
# Explicit bot-authored publication through GitHub's API.
# The default operator-authored flow is agent-publish-z89.
#
# WHY THIS EXISTS
#
# A GitHub App bot signs with its own key, and GitHub cannot verify that key: signing keys attach
# to user ACCOUNTS, and an App bot has no account. So a plain `git push` of a bot commit always
# shows "Unverified", and on a repository whose ruleset requires verified signatures it is refused.
#
# GitHub's documented route for Apps is to create the commit through the API with an installation
# token and NO custom author, committer or signature. GitHub then builds the commit itself, signs
# it with its own web-flow key, and records the verification permanently. Renovate
# (`platformCommit`) and peter-evans/create-pull-request (`sign-commits`) work the same way.
#
# WHY THE GIT DATA API AND NOT createCommitOnBranch
#
# `createCommitOnBranch` carries a path and its contents and no file mode, so a new executable or
# symlink landed as a plain file and needed a human push. The Git Data API builds the commit from
# blobs and a tree, and tree entries carry their mode (100644, 100755, 120000, 160000), so every
# change a local commit can hold can be published. It also makes the publication ATOMIC: every
# commit is built and checked first, unreferenced, and the branch moves once at the end. A failure
# part way leaves the remote branch exactly where it was.
#
# WHY NO CO-AUTHOR TRAILER
#
# GitHub counts a `Co-authored-by` trailer as an author. With vigilant mode on, a commit with an
# author who is not the committer and did not sign it shows "Partially verified", which is what
# the old z89 co-author trailer produced. The bot is the only author now, and the operator who
# directed the work is recorded with a `Requested-by` trailer, which GitHub does not treat as an
# author. Measured on 2026-10-04 against a throwaway branch, rather than assumed.
#
# WHAT IT DOES NOT DO, DELIBERATELY
#
# It does not replace `git commit`. The local commit still happens first, exactly as before, and
# this republishes it afterwards. That ordering is the whole safety argument: `git commit` runs
# the pre-commit hooks, and one of them is the secret scanner. An API call runs no hooks at all,
# so a design that skipped the local commit would produce commits that LOOK more trustworthy
# while actually being checked less. That trade is not worth making.
#
# The scanner earns this on the record: it blocked a commit on 2026-08-17 over a hardcoded region
# and absolute home paths, and the corrections only exist because it fired.
#
# It never touches the working tree or the index. Published commits have the same trees as the
# local ones, so moving the branch onto them changes no file, and a checkout another session is
# editing is safe to publish from.
#
# USAGE
#   gh-signed-commit.sh [remote]        # default remote: origin
#
# Use only when bot authorship was explicitly requested.

set -euo pipefail

REMOTE="${1:-origin}"

die() { printf 'gh-signed-commit: %s\n' "$1" >&2; exit 1; }
say() { printf 'gh-signed-commit: %s\n' "$1"; }

command -v gh >/dev/null || die "the gh CLI is not installed"
command -v jq >/dev/null || die "jq is not installed"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# The App's installation token. Absent means this is not an agent session, in which case the
# operator's own push is the right tool and this script is not.
[ "${AGENT_GH:-0}" = "1" ] || die "AGENT_GH=1 is required, operator sessions push themselves"
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set, this script is for agent sessions only"
[ -n "${AGENT_GH_OWNER:-}" ] || die "AGENT_GH_OWNER is not set; launch through agent-run"
[ -n "${AGENT_GH_BOT_LOGIN:-}" ] || die "AGENT_GH_BOT_LOGIN is not set; launch through agent-run"
[ -n "${AGENT_GH_BOT_EMAIL:-}" ] || die "AGENT_GH_BOT_EMAIL is not set; launch through agent-run"

# Who directed the work. Recorded in the message, never as an author.
REQUESTER="${AGENT_GH_REQUESTER:-z89}"
REQUESTED_TRAILER="Requested-by: ${REQUESTER}"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD; check out a branch"
LOCAL_TIP="$(git rev-parse "refs/heads/$BRANCH")"

URL="$(git config --get "remote.$REMOTE.url")" || die "no such remote: $REMOTE"
SLUG="$(printf '%s' "$URL" | sed -E 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)##; s#\.git$##')"
case "$SLUG" in
  */*) : ;;
  *) die "could not read owner/repo out of remote URL: $URL" ;;
esac
REPO_OWNER="${SLUG%%/*}"
REPO_NAME="${SLUG#*/}"
[ "$REPO_OWNER" = "$AGENT_GH_OWNER" ] ||
  die "repository owner '$REPO_OWNER' does not match selected App profile '$AGENT_GH_OWNER'"

# A branch that has never been published is built on the merge-base with the remote default
# branch, which the remote holds by construction. Nothing is created remotely until every commit
# has been built and checked, so a refusal leaves no empty branch behind.
LSR_RC=0
git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1 || LSR_RC=$?
if [ "$LSR_RC" -eq 2 ]; then
  CREATE=1
  DEFAULT_BRANCH="$(gh api "repos/$REPO_OWNER/$REPO_NAME" --jq '.default_branch')" ||
    die "could not read the default branch of $SLUG"
  git fetch --quiet "$REMOTE" "$DEFAULT_BRANCH" || die "could not fetch $REMOTE/$DEFAULT_BRANCH"
  BASE="$(git merge-base "$LOCAL_TIP" "$REMOTE/$DEFAULT_BRANCH")" ||
    die "$BRANCH shares no history with $REMOTE/$DEFAULT_BRANCH"
  say "$REMOTE/$BRANCH does not exist; it will be created on $(git rev-parse --short "$BASE"), the merge-base with $DEFAULT_BRANCH"
elif [ "$LSR_RC" -eq 0 ]; then
  CREATE=0
  git fetch --quiet "$REMOTE" "$BRANCH" || die "could not fetch $REMOTE/$BRANCH"
  BASE="$(git rev-parse "$REMOTE/$BRANCH")"
  # Anything on the remote that is not in local history means someone else pushed. Publishing
  # over that would be a silent overwrite, so stop and let a human decide how to reconcile.
  BEHIND="$(git rev-list --count "$LOCAL_TIP..$BASE")"
  [ "$BEHIND" -eq 0 ] || die "$REMOTE/$BRANCH has $BEHIND commit(s) not in $BRANCH; rebase first"
else
  die "could not query $REMOTE for $BRANCH (exit $LSR_RC)"
fi

COMMITS="$(git rev-list --reverse "$BASE..$LOCAL_TIP")"
[ -n "$COMMITS" ] || die "nothing to publish, $BRANCH is not ahead of $REMOTE/$BRANCH"
MERGES="$(git rev-list --min-parents=2 "$BASE..$LOCAL_TIP")"
[ -z "$MERGES" ] || die "merge commits are not published by this script: $(printf '%s' "$MERGES" | head -1 | cut -c1-9)"

# Complete every deterministic check before the first API call that creates anything.
for C in $COMMITS; do
  AUTHOR_EMAIL="$(git log -1 --format=%ae "$C")"
  [ "$AUTHOR_EMAIL" = "$AGENT_GH_BOT_EMAIL" ] ||
    die "commit $C is authored as '$AUTHOR_EMAIL', expected '$AGENT_GH_BOT_EMAIL'; the operator publishes their own commits"
  if git log -1 --format=%B "$C" | grep -Eiq '^(co-authored-by|co-signed-by|requested-by):'; then
    die "commit $C already contains an attribution trailer; a co-author makes GitHub show Partially verified, and the publisher adds Requested-by itself"
  fi
done

say "publishing $(printf '%s\n' "$COMMITS" | grep -c .) commit(s) to $SLUG on $BRANCH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# api METHOD PATH REQUEST_FILE -> response on stdout. gh exits non-zero on an HTTP error and
# prints GitHub's message, which is the useful part.
api() {
  gh api --method "$1" "$2" --input "$3" 2>"$WORK/err" || { cat "$WORK/err" >&2; return 1; }
}

# The message exactly as committed: everything after the header block of the raw commit object.
raw_message() { git cat-file commit "$1" | sed '1,/^$/d'; }

# Strip trailing blank lines so the comparison ignores a terminator GitHub may add or drop.
trimmed() { printf '%s\n' "$1" | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'; }

PARENT="$BASE"
PARENT_TREE="$(git rev-parse "$BASE^{tree}")"
PREV="$BASE"
BUILT=""

for C in $COMMITS; do
  [ "$(git rev-parse "$C^")" = "$PREV" ] || die "commit $C does not follow $PREV; history is not linear"
  LOCAL_TREE="$(git rev-parse "$C^{tree}")"

  # One tree entry per changed path. A raw diff-tree line is
  #   :srcmode dstmode srcsha dstsha status<TAB>path
  # --no-renames so a rename is a delete plus an add, which is what a tree edit takes.
  # `change`, not `status`: zsh makes $status a read-only alias for $?.
  : > "$WORK/entries.json"
  while IFS=$'\t' read -r meta path; do
    read -r srcmode dstmode _ dstsha change <<<"${meta#:}"
    case "$change" in
      D)
        type=blob; [ "$srcmode" = "160000" ] && type=commit
        jq -n --arg p "$path" --arg m "$srcmode" --arg t "$type" \
          '{path:$p, mode:$m, type:$t, sha:null}' >> "$WORK/entries.json"
        ;;
      A|M|T)
        if [ "$dstmode" = "160000" ]; then
          # a submodule pointer is a commit id, there is no blob to upload
          jq -n --arg p "$path" --arg s "$dstsha" \
            '{path:$p, mode:"160000", type:"commit", sha:$s}' >> "$WORK/entries.json"
        else
          git cat-file blob "$dstsha" | base64 -w0 > "$WORK/blob.b64"
          jq -n --rawfile c "$WORK/blob.b64" '{content:$c, encoding:"base64"}' > "$WORK/blob.json"
          BLOB="$(api POST "repos/$SLUG/git/blobs" "$WORK/blob.json" | jq -r '.sha')" ||
            die "the API refused the contents of $path in $C; check the App has Contents: write on $SLUG"
          # Git object ids are content hashes, so a matching id proves GitHub holds the same bytes.
          [ "$BLOB" = "$dstsha" ] || die "GitHub stored $path as $BLOB, expected $dstsha"
          jq -n --arg p "$path" --arg m "$dstmode" --arg s "$BLOB" \
            '{path:$p, mode:$m, type:"blob", sha:$s}' >> "$WORK/entries.json"
        fi
        ;;
      *) die "unhandled change status '$change' for $path in $C" ;;
    esac
  done < <(git diff-tree -r --raw --no-renames --no-commit-id --no-abbrev "$C")

  if [ -s "$WORK/entries.json" ]; then
    jq -n --arg base "$PARENT_TREE" --slurpfile e "$WORK/entries.json" \
      '{base_tree:$base, tree:$e}' > "$WORK/tree.json"
    TREE="$(api POST "repos/$SLUG/git/trees" "$WORK/tree.json" | jq -r '.sha')" ||
      die "the API refused the tree for $C"
  else
    TREE="$PARENT_TREE"
  fi
  # The same tree id proves the published commit holds exactly the local files and modes.
  [ "$TREE" = "$LOCAL_TREE" ] || die "GitHub built tree $TREE for $C, expected $LOCAL_TREE"

  BODY="$(trimmed "$(raw_message "$C")")"
  MESSAGE="${BODY}"$'\n\n'"${REQUESTED_TRAILER}"$'\n'

  # No author, no committer, no signature. Any of them makes GitHub skip signing.
  jq -n --arg m "$MESSAGE" --arg t "$TREE" --arg p "$PARENT" \
    '{message:$m, tree:$t, parents:[$p]}' > "$WORK/commit.json"
  api POST "repos/$SLUG/git/commits" "$WORK/commit.json" > "$WORK/created.json" ||
    die "the API refused the commit for $C"

  NEW="$(jq -r '.sha' "$WORK/created.json")"
  [ -n "$NEW" ] && [ "$NEW" != "null" ] || die "no commit id came back for $C"
  [ "$(jq -r '.verification.verified' "$WORK/created.json")" = "true" ] ||
    die "GitHub did not sign the commit for $C ($(jq -r '.verification.reason' "$WORK/created.json")); is GH_TOKEN an App installation token?"
  [ "$(jq -r '.tree.sha' "$WORK/created.json")" = "$LOCAL_TREE" ] || die "the commit for $C points at the wrong tree"
  [ "$(jq -r '.parents | map(.sha) | join(" ")' "$WORK/created.json")" = "$PARENT" ] ||
    die "the commit for $C has the wrong parent"
  [ "$(jq -r '.author.email' "$WORK/created.json")" = "$AGENT_GH_BOT_EMAIL" ] ||
    die "GitHub authored the commit for $C as '$(jq -r '.author.email' "$WORK/created.json")', expected '$AGENT_GH_BOT_EMAIL'"
  [ "$(trimmed "$(jq -j '.message' "$WORK/created.json")")" = "$(trimmed "$MESSAGE")" ] ||
    die "GitHub changed the message of the commit for $C"

  say "  $(git rev-parse --short "$C") -> $(printf '%.9s' "$NEW")  $(printf '%s\n' "$BODY" | head -1)"
  BUILT="$BUILT $NEW"
  PARENT="$NEW"
  PARENT_TREE="$LOCAL_TREE"
  PREV="$C"
done

# Nothing is visible yet. One ref update publishes the whole stack. force:false makes GitHub
# refuse anything but a fast-forward, so a push that landed meanwhile fails this instead of being
# overwritten, the same guarantee expectedHeadOid gave.
if [ "$CREATE" -eq 1 ]; then
  jq -n --arg r "refs/heads/$BRANCH" --arg s "$PARENT" '{ref:$r, sha:$s}' > "$WORK/ref.json"
  api POST "repos/$SLUG/git/refs" "$WORK/ref.json" >/dev/null || die "could not create $REMOTE/$BRANCH; nothing was published"
else
  jq -n --arg s "$PARENT" '{sha:$s, force:false}' > "$WORK/ref.json"
  api PATCH "repos/$SLUG/git/refs/heads/$BRANCH" "$WORK/ref.json" >/dev/null ||
    die "$REMOTE/$BRANCH moved while publishing; nothing was published, fetch and rebase first"
fi

# The published commits are DIFFERENT OBJECTS from the local ones: same trees and messages, new
# ids, because GitHub built and signed them itself. The local branch is moved onto them or the
# next run reads it as ahead again. update-ref with the old value refuses if a commit landed
# locally meanwhile, and since the trees match, the index and working tree stay as they are.
git fetch --quiet "$REMOTE" "$BRANCH" ||
  die "published, but could not fetch $REMOTE/$BRANCH; fetch, then: git update-ref refs/heads/$BRANCH $PARENT $LOCAL_TIP"
[ "$(git rev-parse "$REMOTE/$BRANCH")" = "$PARENT" ] ||
  die "$REMOTE/$BRANCH moved after publication; local $BRANCH left as it was"
git update-ref -m "gh-signed-commit: moved onto the GitHub signed commits" "refs/heads/$BRANCH" "$PARENT" "$LOCAL_TIP" ||
  die "published, but local $BRANCH moved meanwhile; rebase it onto $REMOTE/$BRANCH"
say "local $BRANCH moved onto the published commits, working tree untouched"

# Read every commit back as the world sees it: verified, attributed to the bot, and with the bot
# as the ONLY author. A second author is what turns the badge into "Partially verified".
for NEW in $BUILT; do
  gh api "repos/$SLUG/commits/$NEW" > "$WORK/published.json" || die "could not read $NEW back from GitHub"
  [ "$(jq -r '.commit.verification.verified' "$WORK/published.json")" = "true" ] ||
    die "GitHub reports $NEW as unverified: $(jq -r '.commit.verification.reason' "$WORK/published.json")"
  [ "$(jq -r '.author.login // empty' "$WORK/published.json")" = "$AGENT_GH_BOT_LOGIN" ] ||
    die "GitHub attributed $NEW to '$(jq -r '.author.login // empty' "$WORK/published.json")', expected '$AGENT_GH_BOT_LOGIN'"
  jq -n --arg owner "$REPO_OWNER" --arg name "$REPO_NAME" --arg oid "$NEW" \
    '{
       query: "query($owner: String!, $name: String!, $oid: GitObjectID!) { repository(owner: $owner, name: $name) { object(oid: $oid) { ... on Commit { authors(first: 10) { nodes { email user { login } } } } } } }",
       variables: {owner: $owner, name: $name, oid: $oid}
     }' > "$WORK/authors.json"
  AUTHORS="$(gh api graphql --input "$WORK/authors.json" --jq '[.data.repository.object.authors.nodes[] | .user.login // .email] | join(",")')" ||
    die "could not read the authors of $NEW"
  [ "$AUTHORS" = "$AGENT_GH_BOT_LOGIN" ] || die "GitHub lists the authors of $NEW as '$AUTHORS', expected only '$AGENT_GH_BOT_LOGIN'"
done
say "  verified signature, tree, modes, message, and the bot as the only author"

say "published and VERIFIED: $PARENT"
