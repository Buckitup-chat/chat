.PHONY: check test

check:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix sobelow --verbose
	mix dialyzer --ignore-exit-status

test: 
	rm -rf priv/test_db
	mkdir -p priv/test_db
	mix test --max-failures=1 --cover

commit: check test
	gitui
	

server:
	mix phx.server

iex:
	MIX_ENV=dev iex -S mix phx.server

assets:
	mix assets.deploy

deploy:
	git push gigalixir 

firmware:
	mix phx.digest
	MIX_TARGET=host mix compile assets.deploy

clean:
	mix phx.digest.clean
