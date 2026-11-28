defmodule ChatWeb.Router.ElectricLiveRoutes do
  @moduledoc """
  Routes of the Electric-synced LiveViews (read-only, real-time via PostgreSQL logical
  replication) and the Electric sandboxes.

  Expanded inside `ChatWeb.Router`'s `scope "/", ChatWeb` with `electric_live_routes/0`,
  so the module names below are relative to `ChatWeb`.
  """

  defmacro electric_live_routes do
    quote do
      live_session :electric, on_mount: {ChatWeb.Hooks.SafariSessionHook, :default} do
        live "/electric", ElectricLive.Index, :index
        live "/electric/user_cards", ElectricLive.UserCardsLive.Index, :index
        live "/electric/user_storage", ElectricLive.UserStorageLive.Index, :index
        live "/electric/user_storage_versions", ElectricLive.UserStorageVersionLive.Index, :index
        live "/electric/files", ElectricLive.FilesLive.Index, :index
        live "/electric/file_chunks", ElectricLive.FileChunksLive.Index, :index
        live "/electric/dialog_keys", ElectricLive.DialogKeysLive.Index, :index
        live "/electric/dialog_messages", ElectricLive.DialogMessagesLive.Index, :index

        live "/electric/dialog_message_versions",
             ElectricLive.DialogMessageVersionsLive.Index,
             :index

        live "/electric/dialog_message_reactions",
             ElectricLive.DialogMessageReactionsLive.Index,
             :index

        live "/electric/dialog_message_receipts",
             ElectricLive.DialogMessageReceiptsLive.Index,
             :index

        live "/electric/user_sandbox", ElectricLive.UserSandboxLive.Index, :index
        live "/electric/dialog_sandbox", ElectricLive.DialogSandboxLive.Index, :index
        live "/electric/origins", ElectricLive.OriginsLive.Index, :index
        live "/electric/origin_sandbox", ElectricLive.OriginSandboxLive.Index, :index
        live "/electric/reviews", ElectricLive.ReviewsLive.Index, :index

        live "/electric/review_public_passwords",
             ElectricLive.ReviewPublicPasswordsLive.Index,
             :index

        live "/electric/review_post_rights", ElectricLive.ReviewPostRightsLive.Index, :index
        live "/electric/review_revoke_rights", ElectricLive.ReviewRevokeRightsLive.Index, :index
        live "/electric/review_lists", ElectricLive.ReviewListsLive.Index, :index
        live "/electric/vouch_tokens", ElectricLive.VouchTokensLive.Index, :index
        live "/electric/origin_bots", ElectricLive.OriginBotsLive.Index, :index
        live "/electric/origin_settings", ElectricLive.OriginSettingsLive.Index, :index
        live "/electric/review_write_tokens", ElectricLive.ReviewWriteTokensLive.Index, :index
        live "/electric/review_sandbox", ElectricLive.ReviewSandboxLive.Index, :index
        live "/electric/moderation_sandbox", ElectricLive.ModerationSandboxLive.Index, :index
        live "/electric/origin_reviews", ElectricLive.OriginReviewsLive.Index, :index
        live "/electric/contacts_reader", ElectricLive.ContactsReaderLive.Index, :index
        live "/electric/admin_sandbox", ElectricLive.AdminSandboxLive.Index, :index
        live "/electric/vouch_sandbox", ElectricLive.VouchSandboxLive.Index, :index
      end
    end
  end
end
