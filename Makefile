.PHONY: check test ci-check

check:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused
	mix sobelow --verbose
	mix dialyzer --ignore-exit-status

ci-check: 
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix deps.unlock --check-unused

ci-test:
	mix test --max-failures=3 --cover 

test: 
	rm -rf priv/test_db
	mkdir -p priv/test_db
	mix test --max-failures=1 --cover

commit: check test
	lazygit
	

server:
	mix phx.server

iex:
	MIX_ENV=dev iex -S mix phx.server

assets:
	mix assets.deploy

deploy:
	git push gigalixir 

firmware:
	rm -rf priv/db
	rm -rf priv/admin_db
	MIX_TARGET=host mix do compile, assets.deploy

clean:
	mix phx.digest.clean
