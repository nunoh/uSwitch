.PHONY: dev build-app bundle release install uninstall reset-perms setup-cert cloc clean install-gnome-extension uninstall-gnome-extension

DEV_APP      = dist/uswitch.app
RELEASE_APP  = dist/uSwitch.app
RELEASE_ZIP  = dist/uSwitch-v$(VERSION)-arm64.zip
INSTALLED    = /Applications/uSwitch.app
VERSION     ?= 0.2
LOCAL_SIGN_ID = uSwitch Self-Signed
GNOME_EXT_UUID = uswitch@nh.com
GNOME_EXT_SRC  = gnome-extension/$(GNOME_EXT_UUID)
GNOME_EXT_DST  = $(HOME)/.local/share/gnome-shell/extensions/$(GNOME_EXT_UUID)
GNOME_EXT_OUT  = $(HOME)/.cache/uswitch
GNOME_EXT_ZIP  = $(GNOME_EXT_OUT)/$(GNOME_EXT_UUID).shell-extension.zip

dev: setup-cert
	@swift build -c debug
	@mkdir -p $(DEV_APP)/Contents/MacOS $(DEV_APP)/Contents/Resources
	@cp .build/debug/uswitch $(DEV_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(DEV_APP)/Contents/Resources/AppIcon.icns
	@cp CHANGELOG.md $(DEV_APP)/Contents/Resources/CHANGELOG.md
	@sed 's/__VERSION__/dev/g' Resources/Info.plist > $(DEV_APP)/Contents/Info.plist
	@codesign --sign "$(LOCAL_SIGN_ID)" --force --identifier com.nh.uswitch $(DEV_APP) >/dev/null 2>&1
	@pkill -x uswitch 2>/dev/null || true
	@echo "→ running $(DEV_APP)/Contents/MacOS/uswitch (Ctrl+C to quit)"
	@$(DEV_APP)/Contents/MacOS/uswitch

build-app:
	@swift build -c release
	@rm -rf $(RELEASE_APP)
	@mkdir -p $(RELEASE_APP)/Contents/MacOS $(RELEASE_APP)/Contents/Resources
	@cp .build/release/uswitch $(RELEASE_APP)/Contents/MacOS/uswitch
	@cp Resources/AppIcon.icns $(RELEASE_APP)/Contents/Resources/AppIcon.icns
	@cp CHANGELOG.md $(RELEASE_APP)/Contents/Resources/CHANGELOG.md
	@sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(RELEASE_APP)/Contents/Info.plist
	@file $(RELEASE_APP)/Contents/MacOS/uswitch | grep -q 'arm64'

bundle: setup-cert build-app
	@codesign --sign "$(LOCAL_SIGN_ID)" --force --deep --identifier com.nh.uswitch $(RELEASE_APP) >/dev/null 2>&1
	@echo "✅ built $(RELEASE_APP) (v$(VERSION), Apple Silicon, local signature)"

release: build-app
	@codesign --sign - --force --deep --identifier com.nh.uswitch $(RELEASE_APP) >/dev/null 2>&1
	@rm -f $(RELEASE_ZIP)
	@ditto -c -k --keepParent $(RELEASE_APP) $(RELEASE_ZIP)
	@echo "✅ release archive: $(RELEASE_ZIP) (ad-hoc signed)"

install: bundle
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

install-gnome-extension:
	@mkdir -p $(GNOME_EXT_OUT)
	@gnome-extensions pack $(GNOME_EXT_SRC) --force --out-dir $(GNOME_EXT_OUT)
	@gnome-extensions install --force $(GNOME_EXT_ZIP)
	@echo "installed GNOME extension $(GNOME_EXT_UUID)"
	@echo "enable with: gnome-extensions enable $(GNOME_EXT_UUID)"

uninstall-gnome-extension:
	@gnome-extensions disable $(GNOME_EXT_UUID) 2>/dev/null || true
	@rm -rf $(GNOME_EXT_DST)
	@echo "removed GNOME extension $(GNOME_EXT_UUID)"

# NOTE: reloading the extension requires a full GNOME Shell restart. On Wayland
# (Ubuntu's only session here) that means log out and back in — the shell can't
# restart in place, this mutter build has no nested backend, and neither
# disable/enable nor the ReloadExtension D-Bus call re-reads the JS. So the loop
# is: edit -> make install-gnome-extension -> log out/in -> test.
# Full notes: gnome-extension/DEVELOPING.md
