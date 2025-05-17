.PHONY: check test ci-check empty_db help assets frontend

help:
	@clear
	@grep -E '^[a-zA-Z_-]+:' Makefile | cut -f1 -d: | sort

check:
	mix deps.clean mime --build
	mix compile --warnings-as-errors --all-warnings
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused
	mix sobelow
	MIX_ENV=test mix dialyzer

## Check for files with more than 300 lines
too_long:
	@echo "Checking for files with more than 300 lines..."
	@find lib test -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.heex" \) \
		-exec wc -l {} + | \
		grep -v total | \
		awk '$$1 > 300' | \
		sort -n || \
	echo "No files exceed 300 lines"

ci-check: 
	mix deps.clean mime --build
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused
	mix dialyzer

ci-test:
	npm install --prefix ./assets
	mix assets.deploy
	MIX_ENV=test mix test --max-failures=3 --cover 

test: 
	rm -rf priv/test_db priv/test_admin_db
	mkdir -p priv/test_db priv/test_admin_db
	MIX_ENV=test mix test --max-failures=3 --cover

coverage:
	MIX_ENV=test mix coveralls.html
	open ./cover/excoveralls.html

commit: check test
	lazygit
	

server:
	mix phx.server

iex:
	MIX_ENV=dev iex --sname chat --cookie chat -S mix phx.server --  --no-validate-compile-env

2nd_iex:
	DATA_DIR=priv/2nd/db PORT=4445 MIX_ENV=dev iex --sname chat2 --cookie chat -S mix phx.server --  --no-validate-compile-env

iex_like_prod:
	MIX_ENV=prod \
	PORT=4443 \
	DOMAIN=buckitup.app \
	SECRET_KEY_BASE=IGuZPUcM7Vuq1iPemg6pc7EMwLLmMiVA4stbfDstZPshJ8QDqxBBcVqNnQI6clxi \
	iex -S mix phx.server --  --no-validate-compile-env

assets:
	cp assets/node_modules/@lo-fi/webauthn-local-client/dist/bundlers/walc-external-bundle.js priv/static/
	mix assets.deploy

frontend:
	mix assets.setup
	mix assets.build

deploy:
	git push gigalixir 

empty_db:
	rm -rf priv/db
	rm -rf priv/2nd/*
	rm -rf priv/admin_db
	rm -rf priv/admin_db_v2
	rm -rf priv/test_backup_db
	rm -rf priv/test_admin_db
	rm -rf priv/test_db

firmware: empty_db
	rm -rf _build/prod
	MIX_TARGET=host mix do compile, assets.deploy

clean:
	mix phx.digest.clean
