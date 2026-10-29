#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! command -v pacman >/dev/null 2>&1; then
	die "this script expects Arch/CachyOS pacman"
fi

PKGS=(
	base-devel
	bc
	bison
	flex
	cpio
	openssl
	libelf
	pahole
	python
	perl
	rsync
	zip
	unzip
	lz4
	zstd
	ncurses
	git
	curl
)

missing=()
for p in "${PKGS[@]}"; do
	pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
done

if ((${#missing[@]})); then
	echo "installing: ${missing[*]}"
	sudo pacman -S --needed --noconfirm "${missing[@]}"
else
	echo "dependencies already installed"
fi

for c in make bc bison flex cpio openssl pahole python3 perl rsync zip unzip lz4 zstd git curl; do
	require_cmd "$c"
done
