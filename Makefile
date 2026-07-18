.PHONY: test check swift-parse swift-typecheck data-validate package-validate validate dist-validate gateway xcodegen doctor archive

check:
	cd gateway && npm run check
	cd gateway && npm test
	$(MAKE) swift-parse
	$(MAKE) swift-typecheck

swift-parse:
	swiftc -frontend -parse $$(find iOS/HerdDeck iOS/HerdDeckTests -name '*.swift' -print | sort)

swift-typecheck:
	swiftc -typecheck \
		iOS/HerdDeck/Models/JSONValue.swift \
		iOS/HerdDeck/Models/GatewayModels.swift \
		iOS/HerdDeck/Models/HerdrModels.swift \
		iOS/HerdDeck/Models/AgmsgModels.swift \
		iOS/HerdDeck/Models/TerminalTransportModels.swift \
		iOS/HerdDeck/Models/MissionModels.swift \
		iOS/HerdDeck/Features/Console/TerminalInputMapper.swift \
		iOS/HerdDeck/Features/Console/RichOutputModels.swift \
		iOS/HerdDeck/Networking/GatewayJSONCoding.swift

data-validate:
	@for f in scripts/*.sh; do bash -n "$$f" || exit 1; done
	@python3 -c 'import json,pathlib; [json.loads(p.read_text()) for p in pathlib.Path(".").rglob("*.json")]'
	@python3 -c 'import pathlib,plistlib; [plistlib.loads(p.read_bytes()) for p in pathlib.Path(".").rglob("*.xcprivacy")]'
	@if python3 -c 'import yaml' >/dev/null 2>&1; then python3 -c 'import pathlib,yaml; [yaml.safe_load(p.read_text()) for p in pathlib.Path(".").glob("project*.yml")]'; else echo "skipping project yml validation (PyYAML not installed)"; fi
	@if command -v xcrun >/dev/null 2>&1; then xcrun swift-format lint --recursive iOS; else swift-format lint --recursive iOS; fi

package-validate:
	swift package dump-package --package-path Vendor/MoshBinaryPackage >/dev/null

validate: check data-validate package-validate

dist-validate:
	@test ! -f gateway/config.json
	@test -z "$$(find . -type f \( -name '*.pem' -o -name '*.p12' -o -name '*.mobileprovision' \) -print -quit)"

test:
	cd gateway && npm test

gateway:
	cd gateway && node src/index.mjs

xcodegen:
	xcodegen generate

doctor:
	./scripts/doctor.sh

archive:
	@name="$$(basename "$$(pwd)")"; \
	cd .. && rm -f "$$name-source.zip" "$$name-source.zip.sha256" && \
	zip -r -X "$$name-source.zip" "$$name" \
		-x "$$name/.git/*" "$$name/.build/*" "$$name/DerivedData/*" \
		   "$$name/gateway/config.json" "$$name/*.zip" "$$name/*.ipa" && \
	sha256sum "$$name-source.zip" > "$$name-source.zip.sha256"
