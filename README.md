# Installation

1. Install [`asdf`](https://asdf-vm.com/guide/getting-started.html)
2. Run `asdf install` in project dir
3. Run `mix deps.get`
4. In `assets/js` run `npm install`
5. Run `make iex` in project dir to start server on [`localhost:4000`](http://localhost:4000) and shell. You can exit shell with double `Ctrl-C` and stop the server.


# CSS class nameing conventions

1. `x-` prefixed classes are for logic binding, not for layout
2. `a-` prefixed classes are to aggregate/apply tailwind ones or create our own clases





# Chat

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
