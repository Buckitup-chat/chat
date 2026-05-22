# electric_live/

This directory exists to prove that external clients can consume the Electric shape endpoints provided by the chat application. Each LiveView here acts as a reference implementation demonstrating real-time sync via Phoenix.Sync + ElectricSQL.

Do not use Ecto queries directly — consume data through shape endpoints only (see memory: `feedback_no_direct_db_in_electric`).
