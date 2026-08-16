#!/usr/bin/env bash
# Republishes local commits through GitHub's API so they land VERIFIED.
#
# WHY THIS EXISTS
#
# A GitHub App bot signs with its own key, and GitHub cannot verify that key: signing keys attach
# to user ACCOUNTS, and an App bot has no account. So on a repository whose ruleset requires
# verified signatures, every bot commit trips the rule and needs an operator bypass. Bypassing a
# rule on every commit trains the habit of bypassing it, which is how the rule stops meaning
# anything.
#
# Commits created through `createCommitOnBranch` are signed by GITHUB, server side, with its own
# key. They satisfy the rule honestly instead of going around it.
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
# USAGE
#   gh-signed-commit.sh [remote]        # default remote: origin
#
# Run it after committing locally and instead of `git push`.
set -euo pipefail

REMOTE="${1:-origin}"

die() { printf 'gh-signed-commit: %s\n' "$1" >&2; exit 1; }
say() { printf 'gh-signed-commit: %s\n' "$1"; }

command -v gh >/dev/null || die "the gh CLI is not installed"
command -v jq >/dev/null || die "jq is not installed"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# The App's installation token. Absent means this is not an agent session, in which case the
# operator's own `git push` is the right tool and this script is not.
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set — this script is for agent sessions only, use git push"

[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash before publishing"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD; check out a branch"

URL="$(git config --get "remote.$REMOTE.url")" || die "no such remote: $REMOTE"
SLUG="$(printf '%s' "$URL" | sed -E 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)##; s#\.git$##')"
case "$SLUG" in
  */*) : ;;
  *) die "could not read owner/repo out of remote URL: $URL" ;;
esac

git fetch --quiet "$REMOTE" "$BRANCH" || die "could not fetch $REMOTE/$BRANCH"

COMMITS="$(git rev-list --reverse "$REMOTE/$BRANCH..$BRANCH")"
[ -n "$COMMITS" ] || die "nothing to publish — $BRANCH is not ahead of $REMOTE/$BRANCH"

# Anything on the remote that is not in local history means someone else pushed. Publishing over
# that would be a silent overwrite, so stop and let a human decide how to reconcile.
BEHIND="$(git rev-list --count "$BRANCH..$REMOTE/$BRANCH")"
[ "$BEHIND" -eq 0 ] || die "$REMOTE/$BRANCH has $BEHIND commit(s) not in $BRANCH; rebase first"

HEAD_OID="$(git rev-parse "$REMOTE/$BRANCH")"
# `printf '%s'` emits no trailing newline, so wc -l undercounts by one and a single commit
# reported as "0 commit(s)". Count the lines that are actually there instead.
say "publishing $(printf '%s\n' "$COMMITS" | grep -c .) commit(s) to $SLUG on $BRANCH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for C in $COMMITS; do
  # SPLIT THE RAW MESSAGE, never %s and %b.
  #
  # Git's "subject" is everything up to the first BLANK line, and this project's format —
  # `changelog:` followed immediately by bullets — has no blank line in it at all. So %s returns
  # the entire message with its newlines collapsed to spaces, and %b returns nothing. Publishing
  # that would flatten every commit in the repository to a single line.
  FULL="$(git log -1 --format=%B "$C")"
  SUBJECT="$(printf '%s\n' "$FULL" | head -1)"
  # Leading blank lines are stripped from the body because the API puts one back: it rejoins
  # headline and body as `headline\n\nbody`, which is the git convention. Without the strip, a
  # message already written in that convention gains a SECOND blank line on every publication,
  # and a message republished twice would grow one each time.
  #
  # Measured, not assumed — the 17 August smoke test published `changelog:` immediately followed
  # by a bullet and got a blank line inserted between them.
  BODY="$(printf '%s\n' "$FULL" | tail -n +2 | sed '/./,$!d')"

  # File modes do not survive this API. `fileChanges.additions` carries a path and its contents
  # and nothing else, so a NEW executable or symlink would land as a plain 0644 regular file —
  # silently, and in a repository full of shell scripts that is a broken tree rather than a
  # cosmetic difference. Refuse instead, and say which paths need a human push.
  BADMODE="$(git diff-tree -r --raw --no-renames --no-commit-id "$C" |
    awk '$5 ~ /^[AM]$/ && ($2 == "100755" || $2 == "120000") { print $NF }')"
  if [ -n "$BADMODE" ]; then
    say "commit $C changes files whose mode this API cannot carry:"
    printf '  %s\n' $BADMODE >&2
    die "push these by hand — an executable or symlink would land as a plain file"
  fi

  # --no-renames so a rename is expressed as a delete plus an add, which is what the API takes.
  : > "$WORK/adds.json"
  : > "$WORK/dels.json"
  # `change`, not `status`: zsh makes $status a read-only alias for $?, so that name silently
  # breaks the moment anyone runs this under a shell other than the one in the shebang.
  while IFS=$'\t' read -r meta path; do
    change="$(printf '%s' "$meta" | awk '{print $5}')"
    case "$change" in
      D) jq -n --arg p "$path" '{path:$p}' >> "$WORK/dels.json" ;;
      A|M|T)
        git show "$C:$path" | base64 -w0 > "$WORK/blob.b64"
        jq -n --arg p "$path" --rawfile c "$WORK/blob.b64" '{path:$p, contents:$c}' >> "$WORK/adds.json"
        ;;
      *) die "unhandled change status '$change' for $path in $C" ;;
    esac
  done < <(git diff-tree -r --raw --no-renames --no-commit-id "$C")

  jq -n \
    --arg slug "$SLUG" --arg branch "$BRANCH" \
    --arg headline "$SUBJECT" --arg body "$BODY" --arg oid "$HEAD_OID" \
    --slurpfile adds "$WORK/adds.json" --slurpfile dels "$WORK/dels.json" \
    '{
       query: "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid url } } }",
       variables: { input: {
         branch: { repositoryNameWithOwner: $slug, branchName: $branch },
         message: { headline: $headline, body: $body },
         expectedHeadOid: $oid,
         fileChanges: { additions: $adds, deletions: $dels }
       }}
     }' > "$WORK/request.json"

  RESPONSE="$WORK/response.json"
  if ! gh api graphql --input "$WORK/request.json" > "$RESPONSE" 2>"$WORK/err"; then
    cat "$WORK/err" >&2
    die "the API refused the commit — check the App has Contents: write on $SLUG"
  fi
  # A GraphQL error is a 200 with an `errors` array, so the exit status above proves nothing.
  if jq -e '.errors' "$RESPONSE" >/dev/null 2>&1; then
    jq -r '.errors[].message' "$RESPONSE" >&2
    die "the API returned an error for $C"
  fi

  NEW_OID="$(jq -r '.data.createCommitOnBranch.commit.oid' "$RESPONSE")"
  [ "$NEW_OID" != "null" ] && [ -n "$NEW_OID" ] || die "no commit oid came back for $C"
  say "  $(git log -1 --format=%h "$C") -> $(printf '%.9s' "$NEW_OID")  $SUBJECT"

  # The API takes a headline and a body as separate fields and rejoins them itself, so the
  # message it stores is not guaranteed to be the message that went in — a rejoin with a blank
  # line between them would differ from this project's format by exactly one line. Rather than
  # assume either way, read back what GitHub actually stored and report any difference. A commit
  # whose message quietly changed on publication is worth knowing about the first time, not the
  # tenth.
  gh api "repos/$SLUG/commits/$NEW_OID" --jq '.commit.message' > "$WORK/published.msg" 2>/dev/null || true
  printf '%s\n' "$FULL" > "$WORK/local.msg"
  if [ -s "$WORK/published.msg" ] && ! diff -q <(sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$WORK/local.msg") \
       <(sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$WORK/published.msg") >/dev/null; then
    say "  NOTE: the published message differs from the local one:"
    diff "$WORK/local.msg" "$WORK/published.msg" | sed 's/^/    /' >&2 || true
  fi

  HEAD_OID="$NEW_OID"
done

# The published commits are DIFFERENT OBJECTS from the local ones: same trees and messages, new
# SHAs, because GitHub built and signed them itself. Local history has to be moved onto them or
# the next run reads this branch as ahead again and republishes everything.
git fetch --quiet "$REMOTE" "$BRANCH"
git reset --hard --quiet "$REMOTE/$BRANCH"
say "local $BRANCH reset onto the published commits"

# Verified is the entire point, so it is asserted rather than assumed.
STATE="$(gh api "repos/$SLUG/commits/$HEAD_OID" --jq '.commit.verification.verified')"
if [ "$STATE" = "true" ]; then
  say "published and VERIFIED: $HEAD_OID"
else
  say "WARNING: published, but GitHub reports the signature as unverified"
  gh api "repos/$SLUG/commits/$HEAD_OID" --jq '.commit.verification.reason' >&2
  exit 1
fi
