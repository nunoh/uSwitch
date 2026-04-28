.PHONY: dev install uninstall reset-perms setup-cert cloc clean

DEV_APP      = dist/uswitch.app
RELEASE_APP  = dist/uSwitch.app
INSTALLED    = /Applications/uSwitch.app
VERSION     ?= 0.2
SIGN_ID      = uSwitch Self-Signed

dev: setup-cert
	@swift build -c debug
	@mkdir -p $(DEV_APP)/Contents/MacOS $(DEV_APP)/Contents/Resources
	@cp .build/debug/uswitch $(DEV_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(DEV_APP)/Contents/Resources/AppIcon.icns
	@cp CHANGELOG.md $(DEV_APP)/Contents/Resources/CHANGELOG.md
	@sed 's/__VERSION__/dev/g' Resources/Info.plist > $(DEV_APP)/Contents/Info.plist
	@codesign --sign "$(SIGN_ID)" --force --identifier com.nh.uswitch $(DEV_APP) >/dev/null 2>&1
	@pkill -x uswitch 2>/dev/null || true
	@echo "→ running $(DEV_APP)/Contents/MacOS/uswitch (Ctrl+C to quit)"
	@$(DEV_APP)/Contents/MacOS/uswitch

install: setup-cert
	@swift build -c release
	@rm -rf $(RELEASE_APP)
	@mkdir -p $(RELEASE_APP)/Contents/MacOS $(RELEASE_APP)/Contents/Resources
	@cp .build/release/uswitch $(RELEASE_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(RELEASE_APP)/Contents/Resources/AppIcon.icns
	@cp CHANGELOG.md $(RELEASE_APP)/Contents/Resources/CHANGELOG.md
	@sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(RELEASE_APP)/Contents/Info.plist
	@codesign --sign "$(SIGN_ID)" --force --deep --identifier com.nh.uswitch $(RELEASE_APP) >/dev/null 2>&1
	@pkill -x uswitch 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@cp -R $(RELEASE_APP) $(INSTALLED)
	@open -a $(INSTALLED)
	@echo "✅ installed and launched $(INSTALLED)"

setup-cert:
	@./scripts/setup-cert.sh

uninstall:
	@pkill -x uswitch 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@echo "✅ removed $(INSTALLED) (run 'make reset-perms' to also revoke TCC grants)"

reset-perms:
	@tccutil reset Accessibility com.nh.uswitch >/dev/null 2>&1 || true
	@tccutil reset ScreenCapture com.nh.uswitch >/dev/null 2>&1 || true
	@echo "→ TCC reset for com.nh.uswitch (Accessibility + Screen Recording)"

cloc:
	@cloc Sources/

clean:
	rm -rf .build dist
