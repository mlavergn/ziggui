###############################################
#
# Makefile — ziggui
#
# `make validate` is the pre-commit gate; `make build` is the entry point.
#
###############################################

# Optional include to extend the makefile targets
-include ../styleguide/Makefile.in

.DEFAULT_GOAL := all

.PHONY: build dist demo

# ---------------------------------------------
# Configuration
# ---------------------------------------------

# The released version, read from build.zig.zon (the source of truth).
VERSION := $(shell sed -n -E 's/^[[:space:]]*\.version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' build.zig.zon)

# The Zig source roots `format` and `lint` walk (see ../styleguide/Makefile.in).
ZIG_DIRS := src gallery

# ---------------------------------------------
# Primary workflows
# ---------------------------------------------

# Build, format, and test.
all: build format test
	@echo "done"

# ---------------------------------------------
# Build
# ---------------------------------------------

# Build the library.
build:
	zig build

# Build optimized for release.
dist:
	zig build --release=fast

# Build and launch the gallery (every ziggui component, with theme and
# light/dark switchers) in a window. SDL3 is fetched and built by Zig on first
# use. ReleaseFast because zigui's software fallback is ~10x slower in Debug.
# Pass arguments with `make demo ARGS="--dark"`.
demo:
	zig build run-gallery -Doptimize=ReleaseFast -- $(ARGS)

# ---------------------------------------------
# Cross-compilation
# ---------------------------------------------

# Compile for Linux.
linux:
	zig build -Dtarget=x86_64-linux

# Compile for Windows.
windows:
	zig build -Dtarget=x86_64-windows

# List every target Zig can build for.
targets:
	zig targets

# ---------------------------------------------
# Test
# ---------------------------------------------

# Run the unit test suite.
test:
	zig build test --summary all

# ---------------------------------------------
# Documentation
# ---------------------------------------------

# Build the API docs and serve them locally.
docs:
	zig build docs
	open "http://127.0.0.1:8080" &
	python3 -m http.server -b 127.0.0.1 8080 -d zig-out/docs

# ---------------------------------------------
# Release
# ---------------------------------------------

# Tag the build.zig.zon version (e.g. 1.0.0) and push it.
tag:
	@test -n "$(VERSION)" || { echo "❌ could not read .version from build.zig.zon"; exit 1; }
	git tag -a "$(VERSION)" -m "$(VERSION)"
	git push
	git push --tags

# ---------------------------------------------
# Environment
# ---------------------------------------------

# Open the working copy in SourceTree.
st:
	open -a SourceTree .

# Open the project in the editor.
open:
	code .

# Open the repository on GitHub.
github:
	open "https://github.com/mlavergn/ziggui"

# Clone a fresh working copy.
clone:
	git clone git@github.com:mlavergn/ziggui.git

# Start Claude Code here.
claude:
	claude

# ---------------------------------------------
# Housekeeping
# ---------------------------------------------

# Remove every build artifact.
clean:
	rm -rf .zig-cache
	rm -rf zig-out
