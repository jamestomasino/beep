# beep — Makefile
#
# Detects the host OS and sets BEEP_OS for gprbuild, so you never have to
# remember the flag. All targets are thin wrappers around `alr`.
#
# Override explicitly if you ever need to:
#   make BEEP_OS=linux    build the linux config on this host
#   make BEEP_OS=darwin   build the darwin config on this host
#   make PREFIX=/app      install into a custom prefix (install-system)

SHELL := /bin/bash
PREFIX ?= /usr/local

# Auto-detect OS unless the caller already set BEEP_OS.
BEEP_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]' | grep -oE 'darwin|linux')
export BEEP_OS

help: ## show this help
	@echo "beep — targets:"
	@sed "s/\$$(BEEP_OS)/$(BEEP_OS)/g" $(MAKEFILE_LIST) \
	| grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/  \1|\3/p' \
	| column -t -s '|'

build: ## build for the host OS (BEEP_OS=$(BEEP_OS))
	@echo ">> building beep for BEEP_OS=$(BEEP_OS)"
	alr build

test: build ## build + run the test executables
	./obj/beep_core_tests
	./obj/beep_config_tests

run: build ## build + run the beep CLI
	./obj/beep

install: build ## install into ALR home (~/.config/alire)
	@echo ">> installing beep into ALR home"
	alr install

install-system: build ## install into $(PREFIX) (needs sudo)
	@echo ">> installing beep into $(PREFIX) (may prompt for sudo)"
	alr install --prefix $(PREFIX)

clean: ## remove build artifacts (obj/)
	alr clean

distclean: clean ## remove build artifacts + alire build state
	rm -rf obj alire/build_hash_inputs alire/tmp

.PHONY: help build test run install install-system clean distclean
