# kaju build and install. `make install` is for users without Homebrew;
# Homebrew users install with `brew install aigeano/tap/kaju` instead.
VERSION     ?= 0.1.0
BUNDLE_ID   := io.github.aigeano.kaju
SUPPORT     := $(HOME)/Library/Application Support/kaju
AGENT       := $(HOME)/Library/LaunchAgents/io.github.aigeano.kaju.plist
BREW_AGENT  := $(HOME)/Library/LaunchAgents/homebrew.mxcl.kaju.plist
PYTHON      ?= $(shell command -v python3.13 || command -v python3)
# Python for the iTerm2 helper, written into the app; empty means kaju's own venv.
PYTHON_PATH ?=

.PHONY: build test app venv install uninstall clean

build:
	swift build -c release --disable-sandbox

test:
	swift test

# Assemble build/kaju.app and sign it ad hoc with a stable identifier,
# so macOS permissions refer to kaju rather than to a hash.
app: build
	test -n "$(HOME)"
	rm -rf build/kaju.app
	mkdir -p build/kaju.app/Contents/MacOS build/kaju.app/Contents/Resources
	cp "$$(swift build -c release --disable-sandbox --show-bin-path)/kaju" build/kaju.app/Contents/MacOS/kaju
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > build/kaju.app/Contents/Info.plist
	cp Resources/kaju_iterm2_helper.py Resources/requirements.txt LICENSE NOTICE build/kaju.app/Contents/Resources/
	if [ -n "$(PYTHON_PATH)" ]; then printf '%s\n' "$(PYTHON_PATH)" > build/kaju.app/Contents/Resources/python-path; fi
	codesign --force --sign - --identifier $(BUNDLE_ID) build/kaju.app

venv:
	mkdir -p "$(SUPPORT)"
	"$(PYTHON)" -m venv "$(SUPPORT)/venv"
	"$(SUPPORT)/venv/bin/pip" install --quiet --disable-pip-version-check -r Resources/requirements.txt

install: app venv
	@if [ -f "$(BREW_AGENT)" ]; then echo "kaju is installed with Homebrew; use 'brew upgrade kaju' instead."; exit 1; fi
	-launchctl bootout gui/$$(id -u) "$(AGENT)" 2>/dev/null
	mkdir -p "$(HOME)/Applications" "$(HOME)/Library/LaunchAgents"
	rm -rf "$(HOME)/Applications/kaju.app"
	cp -R build/kaju.app "$(HOME)/Applications/kaju.app"
	sed -e 's#__PROGRAM__#$(HOME)/Applications/kaju.app/Contents/MacOS/kaju#' Resources/launchagent.plist > "$(AGENT)"
	launchctl bootstrap gui/$$(id -u) "$(AGENT)"
	-tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1
	-tccutil reset AppleEvents $(BUNDLE_ID) >/dev/null 2>&1
	@echo "kaju is installed and running. Select Claude Code output, then press ⌃⌥K."

uninstall:
	-launchctl bootout gui/$$(id -u) "$(AGENT)" 2>/dev/null
	rm -f "$(AGENT)"
	rm -rf "$(HOME)/Applications/kaju.app"
	@echo "Removed. Settings and saved reviews remain in $(SUPPORT)."

clean:
	rm -rf .build build
