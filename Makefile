# DynamicIsland -- headless build/run loop.
# project.yml is the source of truth; the .xcodeproj is regenerated, never edited.

SCHEME      := DynamicIsland
CONFIG      := Debug
DERIVED     := .build
APP         := $(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app
BUNDLE_ID   := com.jeffreyotoo.DynamicIsland

.PHONY: all generate build run stop clean log fmtcheck

all: build

generate:
	@xcodegen generate --quiet
	@echo "→ regenerated $(SCHEME).xcodeproj"

build: generate
	@xcodebuild \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(DERIVED) \
		-quiet \
		build

# Full (noisy) build output -- use when `build` fails and you need the detail.
build-verbose: generate
	@xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) build

stop:
	@pkill -x $(SCHEME) 2>/dev/null || true

run: build stop
	@open "$(APP)"
	@echo "→ launched $(APP)"

clean: stop
	@rm -rf $(DERIVED) $(SCHEME).xcodeproj
	@echo "→ cleaned"

log:
	@log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'
