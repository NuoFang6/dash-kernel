#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Local dev machines are Arch/CachyOS; CI runners are Ubuntu.  Both provide
# everything the kernel build needs; the final require_cmd loop is the real
# gate, the package lists only bridge the naming differences.
install_pacman() {
	local -a pkgs=(
		base-devel bc bison flex cpio openssl libelf pahole
		python perl rsync zip unzip lz4 zstd ncurses git curl
	)
	local -a missing=()
	for p in "${pkgs[@]}"; do
		pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
	done
	if ((${#missing[@]})); then
		echo "installing: ${missing[*]}"
		sudo pacman -S --needed --noconfirm "${missing[@]}"
	else
		echo "dependencies already installed"
	fi
}

install_apt() {
	local -a pkgs=(
		build-essential bc bison flex cpio libssl-dev libelf-dev dwarves
		python3 perl rsync zip unzip lz4 zstd libncurses-dev git curl
	)
	echo "installing: ${pkgs[*]}"
	if (( EUID == 0 )); then
		apt-get update -q
		apt-get install -y --no-install-recommends "${pkgs[@]}"
	else
		sudo apt-get update -q
		sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
	fi
}

if command -v pacman >/dev/null 2>&1; then
	install_pacman
elif command -v apt-get >/dev/null 2>&1; then
	install_apt
else
	die "no supported package manager (expect pacman or apt-get)"
fi

for c in make bc bison flex cpio openssl pahole python3 perl rsync zip unzip lz4 zstd git curl; do
	require_cmd "$c"
done
