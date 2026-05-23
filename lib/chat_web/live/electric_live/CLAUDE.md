# electric_live/

This directory exists to prove that external clients can consume the Electric shape endpoints provided by the chat application. Each LiveView here acts as a reference implementation demonstrating real-time sync via Phoenix.Sync + ElectricSQL.

Do not use Ecto queries directly — consume data through shape endpoints only (see memory: `feedback_no_direct_db_in_electric`).

Do not use `Phoenix.Sync.client!()` or the embedded Electric client directly. It bypasses the HTTP layer and returns PostgreSQL's raw `\x` hex encoding for bytea fields instead of base64. Instead, use the `/electric/v1/shapes` endpoint: `Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")`. This routes through `HexToBase64Electric`, which normalizes bytea values to unpadded base64. Note: this does not apply to LiveView streams using `sync_stream_fixed` — the Ecto schema parser handles type conversion automatically.
