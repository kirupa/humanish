.PHONY: app check-code-block-scroll check-critique check-critique-reveal check-editor-clicks check-formatting check-image-cursors check-image-handles check-image-layout check-line-joins check-scroll check-selection-shape check-session check-title-bar-fill check-voiceover check-window clean icons install run test uninstall

app:
	@./Scripts/build-app.sh

check-image-cursors:
	@./Scripts/run-image-cursor-checks.sh

check-image-handles:
	@swift Scripts/check-image-handles.swift

check-editor-clicks:
	@./Scripts/run-editor-click-checks.sh

check-formatting:
	@./Scripts/run-formatting-checks.sh

check-line-joins:
	@./Scripts/run-line-join-checks.sh

check-title-bar-fill:
	@./Scripts/run-title-bar-fill-checks.sh

check-selection-shape:
	@./Scripts/run-selection-shape-checks.sh

check-critique:
	@./Scripts/run-critique-checks.sh

check-critique-reveal:
	@./Scripts/run-critique-reveal-checks.sh

check-code-block-scroll:
	@./Scripts/run-code-block-scroll-checks.sh

check-image-layout:
	@./Scripts/run-image-layout-checks.sh

check-session:
	@./Scripts/run-session-checks.sh

check-scroll:
	@swift Scripts/check-scroll.swift

check-voiceover:
	@./Scripts/run-voiceover-checks.sh

check-window:
	@./Scripts/run-window-checks.sh

icons:
	@swift Scripts/make-icons.swift Packaging ../iOS/Resources/Assets.xcassets/AppIcon.appiconset ../Web/public

install: app
	@./Scripts/install-app.sh

uninstall:
	@./Scripts/uninstall-app.sh

run: app
	@open "$(CURDIR)/build/Humanish.app"

test:
	@./Scripts/run-tests.sh

clean:
	@swift package clean
	@rm -rf -- "$(CURDIR)/build"
