defmodule ChatWeb.Utils do
  @moduledoc "Web-specific util functions"
  use ChatWeb, :verified_routes

  def get_file_url(:file, id, secret) do
    ~p"/get/file/#{Base.encode16(id, case: :lower)}?a=#{Base.url_encode64(secret)}"
  end

  def get_file_url(:image, id, secret) do
    ~p"/get/image/#{Base.encode16(id, case: :lower)}?a=#{Base.url_encode64(secret)}"
  end
end
