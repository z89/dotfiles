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
# key. They satisfy the rule honestly instead of going around it. The publisher also adds one
# canonical z89 co-author trailer, so GitHub attributes the contribution to the operator without
# pretending the bot-authored commit was authored by a human.
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
[ "${AGENT_GH:-0}" = "1" ] || die "AGENT_GH=1 is required — operator sessions must use git push"
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set — this script is for agent sessions only, use git push"
[ -n "${AGENT_GH_OWNER:-}" ] || die "AGENT_GH_OWNER is not set; launch through agent-run"
[ -n "${AGENT_GH_BOT_LOGIN:-}" ] || die "AGENT_GH_BOT_LOGIN is not set; launch through agent-run"
[ -n "${AGENT_GH_BOT_EMAIL:-}" ] || die "AGENT_GH_BOT_EMAIL is not set; launch through agent-run"

COAUTHOR_LOGIN="z89"
COAUTHOR_NAME="z89"
COAUTHOR_EMAIL="30657227+z89@users.noreply.github.com"
COAUTHOR_TRAILER="Co-authored-by: ${COAUTHOR_NAME} <${COAUTHOR_EMAIL}>"

[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash before publishing"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD; check out a branch"

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

git fetch --quiet "$REMOTE" "$BRANCH" || die "could not fetch $REMOTE/$BRANCH"

COMMITS="$(git rev-list --reverse "$REMOTE/$BRANCH..$BRANCH")"
[ -n "$COMMITS" ] || die "nothing to publish — $BRANCH is not ahead of $REMOTE/$BRANCH"

# Anything on the remote that is not in local history means someone else pushed. Publishing over
# that would be a silent overwrite, so stop and let a human decide how to reconcile.
BEHIND="$(git rev-list --count "$BRANCH..$REMOTE/$BRANCH")"
[ "$BEHIND" -eq 0 ] || die "$REMOTE/$BRANCH has $BEHIND commit(s) not in $BRANCH; rebase first"

HEAD_OID="$(git rev-parse "$REMOTE/$BRANCH")"

# Complete every deterministic check before the first remote mutation. The API cannot publish a
# stack atomically, so discovering a malformed later commit after an earlier one was accepted
# would leave a partial publication that needs manual reconciliation.
for C in $COMMITS; do
  AUTHOR_EMAIL="$(git log -1 --format=%ae "$C")"
  [ "$AUTHOR_EMAIL" = "$AGENT_GH_BOT_EMAIL" ] ||
    die "commit $C is authored as '$AUTHOR_EMAIL', expected '$AGENT_GH_BOT_EMAIL'"

  FULL="$(git log -1 --format=%B "$C")"
  if printf '%s\n' "$FULL" | grep -Eiq '^(co-authored-by|co-signed-by):'; then
    die "commit $C already contains an attribution trailer; the publisher adds the canonical z89 trailer"
  fi

  BADMODE="$(git diff-tree -r --raw --no-renames --no-commit-id "$C" |
    awk '{ src = substr($1, 2); dst = $2 }
         (dst == "100755" || dst == "120000") && ($5 == "A" || src != dst) { print $NF }')"
  if [ -n "$BADMODE" ]; then
    say "commit $C changes files whose mode this API cannot carry:"
    printf '  %s\n' $BADMODE >&2
    die "push these by hand — an executable or symlink would land as a plain file"
  fi
done

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

  if [ -n "$BODY" ]; then
    PUBLISH_BODY="${BODY}"$'\n\n'"${COAUTHOR_TRAILER}"
  else
    PUBLISH_BODY="${COAUTHOR_TRAILER}"
  fi
  EXPECTED_MESSAGE="${SUBJECT}"$'\n\n'"${PUBLISH_BODY}"

  # `fileChanges.additions` carries a path and its contents and nothing else, so the API cannot
  # SET a mode. Measured on 17 August against a throwaway branch, rather than assumed:
  #
  #   modifying a file that is already 100755  ->  stays 100755
  #   adding a new file, shebang and all       ->  lands 100644
  #
  # So the two cases it cannot express are a NEW executable or symlink, and a MODE CHANGE on an
  # existing path — `chmod +x` would publish as a content-only commit and quietly not take
  # effect. Ordinary edits to files that are already executable are fine, which is most of them;
  # an earlier version refused those too and made this unusable on a repository full of scripts.
  #
  # $1 carries the source mode with a leading colon, $2 the destination mode.
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
    --arg headline "$SUBJECT" --arg body "$PUBLISH_BODY" --arg oid "$HEAD_OID" \
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

  # Verify every commit immediately: signature, message, tree, primary bot identity, and GitHub's
  # association of the canonical co-author with z89. A final-commit-only check can hide a broken
  # earlier commit in a multi-commit publication.
  gh api "repos/$SLUG/commits/$NEW_OID" > "$WORK/published.json" ||
    die "could not read published commit $NEW_OID back from GitHub"

  VERIFIED="$(jq -r '.commit.verification.verified' "$WORK/published.json")"
  [ "$VERIFIED" = "true" ] ||
    die "GitHub reports $NEW_OID as unverified: $(jq -r '.commit.verification.reason' "$WORK/published.json")"

  jq -j '.commit.message' "$WORK/published.json" > "$WORK/published.msg"
  printf '%s' "$EXPECTED_MESSAGE" > "$WORK/expected.msg"
  if ! diff -q "$WORK/expected.msg" "$WORK/published.msg" >/dev/null; then
    diff -u "$WORK/expected.msg" "$WORK/published.msg" >&2 || true
    die "published message differs from the canonical message for $C"
  fi

  LOCAL_TREE="$(git rev-parse "$C^{tree}")"
  PUBLISHED_TREE="$(jq -r '.commit.tree.sha' "$WORK/published.json")"
  [ "$PUBLISHED_TREE" = "$LOCAL_TREE" ] ||
    die "published tree $PUBLISHED_TREE differs from local tree $LOCAL_TREE for $C"

  PUBLISHED_AUTHOR="$(jq -r '.author.login // empty' "$WORK/published.json")"
  [ "$PUBLISHED_AUTHOR" = "$AGENT_GH_BOT_LOGIN" ] ||
    die "GitHub attributed $NEW_OID to '$PUBLISHED_AUTHOR', expected '$AGENT_GH_BOT_LOGIN'"

  jq -n --arg owner "$REPO_OWNER" --arg name "$REPO_NAME" --arg oid "$NEW_OID" \
    '{
       query: "query($owner: String!, $name: String!, $oid: GitObjectID!) { repository(owner: $owner, name: $name) { object(oid: $oid) { ... on Commit { authors(first: 100) { nodes { email user { login } } } } } } }",
       variables: {owner: $owner, name: $name, oid: $oid}
     }' > "$WORK/authors-request.json"
  gh api graphql --input "$WORK/authors-request.json" > "$WORK/authors-response.json" ||
    die "could not verify GitHub author association for $NEW_OID"
  jq -e --arg login "$COAUTHOR_LOGIN" --arg email "$COAUTHOR_EMAIL" \
    '.data.repository.object.authors.nodes[] | select(.user.login == $login and .email == $email)' \
    "$WORK/authors-response.json" >/dev/null ||
    die "GitHub did not associate canonical co-author $COAUTHOR_LOGIN with $NEW_OID"

  say "  verified signature, tree, bot author, and z89 co-author"

  HEAD_OID="$NEW_OID"
done

# The published commits are DIFFERENT OBJECTS from the local ones: same trees and messages, new
# SHAs, because GitHub built and signed them itself. Local history has to be moved onto them or
# the next run reads this branch as ahead again and republishes everything.
git fetch --quiet "$REMOTE" "$BRANCH"
[ "$(git rev-parse "$REMOTE/$BRANCH")" = "$HEAD_OID" ] ||
  die "$REMOTE/$BRANCH moved after publication; refusing to reset local history"
git reset --hard --quiet "$REMOTE/$BRANCH"
say "local $BRANCH reset onto the published commits"

say "published, VERIFIED, and attributed to z89: $HEAD_OID"
