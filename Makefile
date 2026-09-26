# The Command Line Tools ship swift-testing's macro plugin outside the default search path.
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

.PHONY: test app run install icon logs release
test:
	swift test $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))
app:
	Scripts/bundle.sh
run: app
	pkill -x AIResetRunner || true
	open build/AIResetRunner.app
install: app
	pkill -x AIResetRunner || true
	rm -rf /Applications/AIResetRunner.app
	cp -R build/AIResetRunner.app /Applications/
	open /Applications/AIResetRunner.app
icon:
	swift Scripts/make-icon.swift
logs:
	/usr/bin/log stream --level debug --predicate 'subsystem == "com.local.airesetrunner"'

# Bump VERSION first. Publishes build/AIResetRunner.zip, which the in-app updater downloads.
release: test app
	gh release create v$$(cat VERSION) build/AIResetRunner.zip --title "v$$(cat VERSION)" --generate-notes
