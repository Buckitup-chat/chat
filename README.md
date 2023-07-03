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


# Logging recommendation

Using IO data as arguments to the logging function will give a little performance:
  * https://elixirforum.com/t/understanding-iodata/3932/3
  * https://10consulting.com/2016/10/28/elixir-io-lists/


# Technical info

  * [Encryption](./lib/enigma/encryption.livemd)
  * [DB structure](./lib/chat/db_structures.livemd)
  * [AdminDB structure](./lib/chat/admin_db_structures.livemd)
  * [Room approval flow](./lib/chat/rooms/approve_flow.livemd)
  * [DB Prioritization](./lib/chat/db/prioritization.livemd)
  * [DB and Device Supervision](./lib/chat/db/supervision.livemd)
  * [Naive API File upload](./lib/naive_api/upload_files.livemd)
  * [Cargo scenario](.lib/chat/sync/cargo_scenario.livemd)