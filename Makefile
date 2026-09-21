# DynamicIsland -- headless build/run loop.
# project.yml is the source of truth; the .xcodeproj is regenerated, never edited.

SCHEME      := DynamicIsland
CONFIG      := Debug
DERIVED     := .build
APP         := $(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app
BUNDLE_ID   := com.jeffreyotoo.DynamicIsland

.PHONY: all adapter generate build build-verbose run stop clean log test snapshots

# mediaremote-adapter: MediaRemote is entitlement-gated for third-party apps, so
# the app shells out to Apple-signed /usr/bin/perl, which loads this framework.
# Built from the pinned submodule rather than vendored as a binary.
ADAPTER_SRC   := Vendor/mediaremote-adapter
ADAPTER_BUILD := $(DERIVED)/adapter
ADAPTER_FW    := $(ADAPTER_BUILD)/MediaRemoteAdapter.framework

adapter: $(ADAPTER_FW)

$(ADAPTER_FW): $(ADAPTER_SRC)/CMakeLists.txt
	@cmake -S $(ADAPTER_SRC) -B $(ADAPTER_BUILD) -DCMAKE_BUILD_TYPE=Release > /dev/null
	@cmake --build $(ADAPTER_BUILD) --config Release > /dev/null
	@echo "→ built MediaRemoteAdapter.framework"

all: build

generate: adapter
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

# Headless regression harnesses. Each prints RESULT: PASS / FAIL and exits.
BIN := $(APP)/Contents/MacOS/$(SCHEME)

test: build stop
	@echo "== click routing =="        && $(BIN) -DISelfTest YES
	@echo "== synthetic notch =="      && $(BIN) -DISelfTest YES -DIForceSyntheticNotch YES
	@echo "== debug overlay =="        && $(BIN) -DISelfTest YES -DIDebugOverlay YES
	@echo "== lifecycle =="            && $(BIN) -DILifecycleTest YES
	@echo "== morph top edge =="       && $(BIN) -DICaptureMorph "$(CURDIR)/$(DERIVED)/live" | tail -3
	@echo "== click + transport =="    && $(BIN) -DIClickTest YES | tail -2

# Renders the island to PNGs -- an LSUIElement app is invisible to screen capture.
snapshots: build stop
	@$(BIN) -DIExportSnapshot "$(CURDIR)/$(DERIVED)/island"

clean: stop
	@rm -rf $(DERIVED) $(SCHEME).xcodeproj
	@echo "→ cleaned"

log:
	@log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'
