APP_NAME := VoiceFlow
APP := build/$(APP_NAME).app

# Sign with the stable local identity when it exists (see `make cert`) so the
# TCC permissions (mic, Accessibility) survive rebuilds; ad-hoc otherwise.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -q "VoiceFlow Dev" && echo VoiceFlow Dev || echo -)

.PHONY: app run install test clean cert whisper model ai icon dist

whisper:
	./scripts/build-whisper.sh

icon: build/AppIcon.icns

build/AppIcon.icns: scripts/make-icon.swift
	mkdir -p build
	swift scripts/make-icon.swift
	iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

app: build/AppIcon.icns
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP)/Contents/MacOS/
	cp scripts/Info.plist $(APP)/Contents/Info.plist
	cp build/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP) (signed: $(SIGN_ID))"

# Release archive for GitHub: zip preserving the bundle structure.
dist: app
	cd build && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip
	@echo "build/$(APP_NAME).zip"

cert:
	./scripts/make-signing-cert.sh

run: app
	pkill -x $(APP_NAME) || true
	open $(APP)

install: app
	pkill -x $(APP_NAME) || true
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	@echo "Installed to /Applications"

test:
	swift run voiceflow-tests

# Downloads the Whisper model manually (the app also does this on first run).
model:
	mkdir -p "$$HOME/Library/Application Support/VoiceFlow/models"
	curl -L -C - -o "$$HOME/Library/Application Support/VoiceFlow/models/ggml-large-v3-turbo-q5_0.bin" \
		"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"

# Sets up the AI cleanup step: Ollama daemon + a small multilingual model.
ai:
	brew list ollama >/dev/null 2>&1 || brew install ollama
	brew services start ollama
	sleep 2
	ollama pull qwen3:4b-instruct

clean:
	rm -rf .build build
