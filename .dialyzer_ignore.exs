# Dialyzer false positives caused by too-narrow typespecs in dependencies.
# Remove an entry once the upstream spec is fixed.
[
  # phoenix_sync 0.6.1: `transact_opts()` is typed `[parse_opts() | keyword()]`, i.e. a list
  # of lists, so any plain keyword opts (`format:`, `timeout:`) "break the contract" of
  # `Phoenix.Sync.Writer.apply/4`. The no_return warnings cascade from that call.
  {"lib/chat/pq/ingest.ex", :call},
  {"lib/chat/pq/ingest.ex", :no_return},
  {"lib/chat/review_bot/worker.ex", :no_return},

  # electric_client: `Fetch.Response.body` is typed `[map()]`, but error responses carry the
  # decoded JSON map (`%{"error" => "read_session_required", ...}`). The unused_fun warning
  # cascades from the "impossible" 401 branch.
  {"lib/chat_web/live/electric_live/sandbox_gated_fetch.ex", :pattern_match},
  {"lib/chat_web/live/electric_live/sandbox_gated_fetch.ex", :unused_fun},

  # phoenix 1.8.3: `Phoenix.Socket.transport` is typed `atom`, but `Phoenix.ChannelTest.join/4`
  # matches it against `{Phoenix.ChannelTest, sup}`, so every `subscribe_and_join` call compiled
  # into test/support "has no local return".
  {"test/support/webrtc_channel_helpers.ex", :no_return}
]
