.PHONY: check test ci-check

check:
	mix deps.clean mime --build
	mix compile --warnings-as-errors --all-warnings
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused
	mix sobelow --verbose
	mix dialyzer --ignore-exit-status

ci-check: 
	mix deps.clean mime --build
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused

ci-test:
	npm install --prefix ./assets
	mix assets.deploy
	MIX_ENV=test mix test --max-failures=3 --cover 

test: 
	rm -rf priv/test_db
	mkdir -p priv/test_db
	MIX_ENV=test mix test --max-failures=3 --cover

coverage:
	MIX_ENV=test mix coveralls.html
	open ./cover/excoveralls.html

commit: check test
	lazygit
	

server:
	mix phx.server

iex:
	MIX_ENV=dev iex --sname chat --cookie chat -S mix phx.server

assets:
	mix assets.deploy

deploy:
	git push gigalixir 

firmware:
	rm -rf priv/db
	rm -rf priv/admin_db
	rm -rf priv/admin_db_v2
	rm -rf priv/test_backup_db
	rm -rf priv/test_admin_db
	rm -rf priv/test_db
	MIX_TARGET=host mix do compile, assets.deploy

clean:
	mix phx.digest.clean
