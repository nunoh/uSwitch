.PHONY: dev install uninstall reset-perms cloc clean

DEV_APP     = dist/uswitch.app
RELEASE_APP = dist/uSwitch.app
INSTALLED   = /Applications/uSwitch.app
VERSION    ?= 0.1

dev:
	@swift build -c debug
	@mkdir -p $(DEV_APP)/Contents/MacOS $(DEV_APP)/Contents/Resources
	@cp .build/debug/uswitch $(DEV_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(DEV_APP)/Contents/Resources/AppIcon.icns
	@sed 's/__VERSION__/dev/g' Resources/Info.plist > $(DEV_APP)/Contents/Info.plist
	@codesign --sign - --force $(DEV_APP) >/dev/null 2>&1
	@pkill -x uswitch 2>/dev/null || true
	@echo "→ running $(DEV_APP)/Contents/MacOS/uswitch (Ctrl+C to quit)"
	@$(DEV_APP)/Contents/MacOS/uswitch

install: reset-perms
	@swift build -c release
	@rm -rf $(RELEASE_APP)
	@mkdir -p $(RELEASE_APP)/Contents/MacOS $(RELEASE_APP)/Contents/Resources
	@cp .build/release/uswitch $(RELEASE_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(RELEASE_APP)/Contents/Resources/AppIcon.icns
	@sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(RELEASE_APP)/Contents/Info.plist
	@codesign --sign - --force --deep $(RELEASE_APP) >/dev/null 2>&1
	@pkill -x uswitch 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@cp -R $(RELEASE_APP) $(INSTALLED)
	@echo "✅ installed to $(INSTALLED) — launch via Spotlight (⌘Space → uSwitch)"

uninstall: reset-perms
	@pkill -x uswitch 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@echo "✅ removed $(INSTALLED)"

reset-perms:
	@tccutil reset Accessibility com.nh.uswitch >/dev/null 2>&1 || true
	@tccutil reset ScreenCapture com.nh.uswitch >/dev/null 2>&1 || true
	@echo "→ TCC reset for com.nh.uswitch (Accessibility + Screen Recording)"

cloc:
	@cloc Sources/

clean:
	rm -rf .build dist
