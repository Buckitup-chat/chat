defmodule ChatWeb.ElectricLive.Index.SandboxCards do
  @moduledoc "Electric index cards linking to the sandboxes."

  @doc "Cards in display order."
  def all do
    [
      %{
        href: "/electric/user_sandbox",
        icon_color: "text-green-600",
        icon_path: "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
        label: "User API Sandbox",
        title: "API Testing",
        shapes: "user_card, user_storage"
      },
      %{
        href: "/file_sandbox.html",
        icon_color: "text-orange-600",
        icon_path:
          "M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12",
        label: "File Sandbox",
        title: "Upload / Download",
        shapes: "file, file_chunk"
      },
      %{
        href: "/electric/dialog_sandbox",
        icon_color: "text-teal-600",
        icon_path:
          "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
        label: "Dialog Sandbox",
        title: "Encrypted Chat",
        shapes: "dialog_keys, dialog_messages"
      },
      %{
        href: "/electric/origin_sandbox",
        icon_color: "text-orange-600",
        icon_path:
          "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
        label: "Origin Sandbox",
        title: "Owner Operations",
        description: "Owner operations: create/update/delete origins, export identity",
        shapes: "user_card, origin"
      },
      %{
        href: "/electric/review_sandbox",
        icon_color: "text-yellow-600",
        icon_path:
          "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
        label: "Review Sandbox",
        title: "Review Pipeline",
        shapes: "review, review_list, review_public_passwords, dialog_keys, dialog_messages"
      },
      %{
        href: "/electric/moderation_sandbox",
        icon_color: "text-red-600",
        icon_path:
          "M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z",
        label: "Moderation Sandbox",
        title: "Origin Console",
        description: "Origin Console: moderation, settings, review bots, write tokens",
        shapes: "review_post_right, review_public_passwords"
      },
      %{
        href: "/electric/origin_reviews",
        icon_color: "text-yellow-600",
        icon_path:
          "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
        label: "Origin Reviews",
        title: "Public Viewer",
        shapes: "origin, review, review_public_passwords"
      },
      %{
        href: "/electric/contacts_reader",
        icon_color: "text-violet-600",
        icon_path:
          "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
        label: "Contacts Reader",
        title: "Contact Reviews",
        shapes: "review_list, review, dialog_keys, dialog_messages"
      },
      %{
        href: "/electric/vouch_sandbox",
        icon_color: "text-emerald-600",
        icon_path:
          "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
        label: "Vouch Sandbox",
        title: "Trust Tokens",
        shapes: "vouch_tokens"
      },
      %{
        href: "/electric/admin_sandbox",
        icon_color: "text-gray-700",
        icon_path:
          "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065zM15 12a3 3 0 11-6 0 3 3 0 016 0z",
        label: "Admin Sandbox",
        title: "Device & Gate",
        shapes: "AdminDb (CubDB)"
      }
    ]
  end
end
