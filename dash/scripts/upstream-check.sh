#!/usr/bin/env bash
# Compare every submodule's pinned commit against the head of its tracked
# branch on the remote.  Read-only: git ls-remote only, no clone/fetch, works
# with uninitialized submodules.  Exit 1 when any submodule drifted.
#
# Usage: bash dash/scripts/upstream-check.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

drift=0
printf '%-40s %-14s %-14s %s\n' "submodule" "pinned" "remote head" "drift"

for key in $(git config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$'); do
	name="${key%.path}"
	name="${name#submodule.}"
	path="$(git config --file .gitmodules --get "submodule.${name}.path")"
	url="$(git config --file .gitmodules --get "submodule.${name}.url")"
	branch="$(git config --file .gitmodules --get "submodule.${name}.branch" || true)"
	pin="$(git rev-parse "HEAD:$path")"
	if [[ -n "$branch" ]]; then
		ref="refs/heads/$branch"
	else
		ref="HEAD"
	fi
	head="$(git ls-remote "$url" "$ref" 2>/dev/null | awk 'NR==1{print $1}' || true)"
	if [[ -z "$head" ]]; then
		printf '%-40s %-14.14s %-14s %s\n' "$path" "$pin" "(unreachable)" "YES"
		drift=1
	elif [[ "$head" != "$pin" ]]; then
		printf '%-40s %-14.14s %-14.14s %s\n' "$path" "$pin" "$head" "YES ($ref)"
		drift=1
	else
		printf '%-40s %-14.14s %-14.14s %s\n' "$path" "$pin" "$head" "no"
	fi
done

if ((drift)); then
	echo
	echo "drift detected: pinned submodule(s) differ from their remote branch head."
	echo "bump via .github/workflows/bump-submodule.yml, or manually:"
	echo "  git submodule update --init --depth 1 <path>"
	echo "  git -C <path> fetch --depth 1 origin <branch> && git -C <path> checkout --detach <head>"
	echo "  # then update versions.env pins for BakaSU/SUSFS if applicable, and run make -C dash source patches"
	exit 1
fi
echo
echo "all submodules at their remote branch head"
