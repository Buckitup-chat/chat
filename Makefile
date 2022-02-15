.PHONY: check test

check:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	mix sobelow --verbose
	mix dialyzer --ignore-exit-status

test: 
	mix test --cover

server:
	mix phx.server

iex:
	iex -S mix phx.server

assets:
	mix assets.deploy

deploy:
	git push gigalixir 

firmware:
	MIX_TARGET=host mix compile assets.deploy
