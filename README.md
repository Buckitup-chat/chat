# Installation

1. Install [`asdf`](https://asdf-vm.com/guide/getting-started.html)
2. Run `asdf install` in project dir
3. Run `mix deps.get`
4. In `assets/js` run `npm install`
5. Run `make iex` in project dir to start server on [`localhost:4000`](http://localhost:4000) and shell. You can exit shell with double `Ctrl-C` and stop the server.


# CSS class naming conventions

1. `x-` prefixed classes are for logic binding, not for layout
2. `a-` prefixed classes are to aggregate/apply tailwind ones or create our own classes
3. `t-` prefixed classes are for test anchors


# Technical info

  * [DB structure](./lib/chat/db_structures.livemd)

