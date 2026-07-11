APP_NAME := VoiceFlow
APP := build/$(APP_NAME).app

# Sign with the stable local identity when it exists (see `make cert`) so the
# TCC permissions (mic, Accessibility) survive rebuilds; ad-hoc otherwise.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -q "VoiceFlow Dev" && echo VoiceFlow Dev || echo -)

.PHONY: app run install test clean cert whisper model ai

whisper:
	./scripts/build-whisper.sh

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/$(APP_NAME) $(APP)/Contents/MacOS/
	cp scripts/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP) (signed: $(SIGN_ID))"

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
	ollama pull gemma3:4b

clean:
	rm -rf .build build
