SHELL := /bin/bash
.DEFAULT_GOAL := build

.PHONY: deps toolchain source patches config build boot all clean distclean notes notes-check

deps:
	bash scripts/install-deps.sh

toolchain:
	bash scripts/fetch-toolchain.sh

source:
	bash scripts/sync-aosp.sh

patches: source
	bash scripts/apply-patches.sh

config: toolchain patches
	bash scripts/configure.sh

build: config
	bash scripts/build.sh

boot: build
	bash scripts/make-boot.sh

notes:
	python3 scripts/collect-notes.py

notes-check:
	python3 scripts/collect-notes.py --check

all: boot

clean:
	rm -rf out

distclean: clean
	rm -rf src toolchains
