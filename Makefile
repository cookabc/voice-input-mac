# Murmur — macOS Fn-key dictation tool
SHELL    := /bin/zsh
APP_NAME := Murmur
BUNDLE   := com.advance.murmur
STAGE    := .stage/$(APP_NAME).app

# Resolve coli path
COLI_PATH ?= $(shell command -v coli 2>/dev/null)

.PHONY: build run install clean stage

# ── Build (release) ────────────────────────────────────────────────────────────
build:
	swift build -c release

# ── Stage .app bundle ──────────────────────────────────────────────────────────
stage: build
	@bash dev.sh --release --no-run

# ── Run ────────────────────────────────────────────────────────────────────────
run: stage
	@pkill -f '$(APP_NAME).app/Contents/MacOS/$(APP_NAME)' 2>/dev/null || true
	@sleep 0.3
	open "$(STAGE)"

# ── Install to /Applications ──────────────────────────────────────────────────
install: stage
	@pkill -f '$(APP_NAME).app/Contents/MacOS/$(APP_NAME)' 2>/dev/null || true
	@sleep 0.3
	rm -rf /Applications/$(APP_NAME).app
	cp -R "$(STAGE)" /Applications/$(APP_NAME).app
	codesign --force --deep --sign - /Applications/$(APP_NAME).app
	@echo "Installed → /Applications/$(APP_NAME).app"

# ── Clean ──────────────────────────────────────────────────────────────────────
clean:
	swift package clean
	rm -rf .build .stage
