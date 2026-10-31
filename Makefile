CONFIG ?= release
VERSION ?= 1.1.0
UNIVERSAL ?= 1

.PHONY: setup project app build run dmg clean check

## Verify toolchain, manifest and dependency graph.
setup:
	./scripts/setup.sh

## Regenerate OpenCodeHub.xcodeproj from project.yml (needs XcodeGen).
project:
	xcodegen generate --spec project.yml

## Build the native .app (XcodeGen + xcodebuild when available).
app:
	CONFIG=$(CONFIG) VERSION=$(VERSION) UNIVERSAL=$(UNIVERSAL) ./scripts/build-app.sh

build:
	swift build -c $(CONFIG)

run: app
	open "build/Open Code Hub.app"

dmg: app
	VERSION=$(VERSION) ./scripts/make-dmg.sh

check:
	swift build -c debug

clean:
	rm -rf .build build OpenCodeHub.xcodeproj
