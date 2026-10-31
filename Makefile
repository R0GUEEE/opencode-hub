CONFIG ?= release
VERSION ?= 1.0.0
UNIVERSAL ?= 0

.PHONY: setup resolve app build run dmg clean check

## Verify toolchain, manifest and dependency graph; then build.
setup:
	./scripts/setup.sh

## SwiftPM only: resolve the package graph without building.
resolve:
	swift package resolve

app:
	CONFIG=$(CONFIG) VERSION=$(VERSION) UNIVERSAL=$(UNIVERSAL) ./scripts/build-app.sh

build:
	swift build -c $(CONFIG)

run: app
	open "build/OpenCode Hub.app"

dmg: app
	VERSION=$(VERSION) ./scripts/make-dmg.sh

check:
	swift build -c debug

clean:
	rm -rf .build build
