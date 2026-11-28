defmodule ChatWeb.ElectricLive.Index.ShapeCards do
  @moduledoc "Electric index cards linking to the shape list LiveViews."

  @doc "Cards in display order."
  def all do
    [
      %{
        href: "/electric/user_cards",
        icon_color: "text-blue-600",
        icon_path:
          "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
        label: "User Cards",
        title: "Post-Quantum Users",
        shapes: "user_card"
      },
      %{
        href: "/electric/user_storage",
        icon_color: "text-purple-600",
        icon_path:
          "M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4",
        label: "User Storage",
        title: "Encrypted Storage",
        shapes: "user_storage"
      },
      %{
        href: "/electric/user_storage_versions",
        icon_color: "text-indigo-600",
        icon_path: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
        label: "Storage Versions",
        title: "Version History",
        shapes: "user_storage (versions)"
      },
      %{
        href: "/electric/files",
        icon_color: "text-indigo-600",
        icon_path:
          "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
        label: "Files",
        title: "File Manifests",
        shapes: "file"
      },
      %{
        href: "/electric/file_chunks",
        icon_color: "text-purple-600",
        icon_path:
          "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4",
        label: "File Chunks",
        title: "Chunk Data",
        shapes: "file_chunk"
      },
      %{
        href: "/electric/dialog_keys",
        icon_color: "text-teal-600",
        icon_path:
          "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
        label: "Dialog Keys",
        title: "Key Exchange",
        shapes: "dialog_keys"
      },
      %{
        href: "/electric/dialog_messages",
        icon_color: "text-cyan-600",
        icon_path:
          "M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z",
        label: "Dialog Messages",
        title: "Message Tips",
        shapes: "dialog_messages"
      },
      %{
        href: "/electric/dialog_message_versions",
        icon_color: "text-amber-600",
        icon_path: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
        label: "Message Versions",
        title: "Version History",
        shapes: "dialog_messages (versions)"
      },
      %{
        href: "/electric/dialog_message_reactions",
        icon_color: "text-pink-600",
        icon_path:
          "M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
        label: "Reactions",
        title: "Emoji Reactions",
        shapes: "dialog_message_reactions"
      },
      %{
        href: "/electric/dialog_message_receipts",
        icon_color: "text-emerald-600",
        icon_path: "M5 13l4 4L19 7",
        label: "Receipts",
        title: "Read/Delivered",
        shapes: "dialog_message_receipts"
      },
      %{
        href: "/electric/origins",
        icon_color: "text-orange-600",
        icon_path:
          "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
        label: "Origins",
        title: "Business Entities",
        shapes: "origin"
      },
      %{
        href: "/electric/reviews",
        icon_color: "text-yellow-600",
        icon_path:
          "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
        label: "Reviews",
        title: "Review Records",
        shapes: "review"
      },
      %{
        href: "/electric/review_public_passwords",
        icon_color: "text-yellow-500",
        icon_path:
          "M15 12a3 3 0 11-6 0 3 3 0 016 0z M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z",
        label: "Public Passwords",
        title: "Public Visibility",
        shapes: "review_public_passwords"
      },
      %{
        href: "/electric/review_post_rights",
        icon_color: "text-green-600",
        icon_path:
          "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
        label: "Post Rights",
        title: "Publish Envelopes",
        shapes: "review_post_right"
      },
      %{
        href: "/electric/review_revoke_rights",
        icon_color: "text-red-600",
        icon_path:
          "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636",
        label: "Revoke Rights",
        title: "Revoke Envelopes",
        shapes: "review_revoke_right"
      },
      %{
        href: "/electric/review_lists",
        icon_color: "text-violet-600",
        icon_path:
          "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01",
        label: "Review Lists",
        title: "Password Lists",
        shapes: "review_list"
      },
      %{
        href: "/electric/vouch_tokens",
        icon_color: "text-emerald-600",
        icon_path:
          "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
        label: "Vouch Tokens",
        title: "Trust Tokens",
        shapes: "vouch_tokens"
      },
      %{
        href: "/electric/origin_bots",
        icon_color: "text-rose-600",
        icon_path:
          "M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
        label: "Origin Bots",
        title: "Bot Identities",
        shapes: "origin_bots"
      },
      %{
        href: "/electric/origin_settings",
        icon_color: "text-slate-600",
        icon_path:
          "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065zM15 12a3 3 0 11-6 0 3 3 0 016 0z",
        label: "Origin Settings",
        title: "Per-Origin Config",
        shapes: "origin_settings"
      },
      %{
        href: "/electric/review_write_tokens",
        icon_color: "text-amber-600",
        icon_path:
          "M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z",
        label: "Write Tokens",
        title: "Token Lifecycle",
        shapes: "review_write_tokens"
      }
    ]
  end
end
