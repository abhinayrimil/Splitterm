# Common tasks. Run `make help`.
VERSION ?= 1.0.0

.PHONY: help build test run app dmg install clean

help:
	@echo "make build    - debug build"
	@echo "make test     - run unit tests"
	@echo "make run      - build and run the app bundle"
	@echo "make app      - release .app + .dmg in dist/ (universal, ad-hoc signed)"
	@echo "make install  - build and copy Splitterm.app to /Applications"
	@echo "Signing/notarising: SIGN_IDENTITY=... NOTARY_PROFILE=... make app"

build:
	swift build

test:
	swift test

app dmg:
	VERSION=$(VERSION) scripts/build-app.sh

run:
	UNIVERSAL=0 VERSION=$(VERSION) scripts/build-app.sh
	open dist/Splitterm.app

install: app
	rm -rf /Applications/Splitterm.app
	cp -R dist/Splitterm.app /Applications/
	@echo "Installed /Applications/Splitterm.app"

clean:
	rm -rf .build dist
