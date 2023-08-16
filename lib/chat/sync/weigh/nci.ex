defmodule Chat.Sync.Weigh.NCI do
  @moduledoc """
  NCI weigh protocol helpers
  """

  def parse_weight_response(binary) do
    Regex.named_captures(~r/\n *(?<weight>\S+)\r\n(?<status>.{2,3})\r\x03/m, binary)
    |> case do
      %{"weight" => weight, "status" => status} -> {:ok, {weight, status}}
      x -> {:error, x}
    end
  end

  def parse_status(binary) do
    case binary do
      <<
        3::4,
        eeprom_er::1,
        ram_er::1,
        zero::1,
        motion::1,
        7::4,
        calibr_er::1,
        rom_er::1,
        over_cap::1,
        under_cap::1,
        3::4,
        init_zero_er::1,
        net_w::1,
        range::2
      >> ->
        %{
          eeprom_error?: eeprom_er == 1,
          ram_error?: ram_er == 1,
          zero?: zero == 1,
          in_motion?: motion == 1,
          calibration_error?: calibr_er == 1,
          rom_error?: rom_er == 1,
          over_capacity?: over_cap == 1,
          under_capacity?: under_cap == 1,
          init_zero_error?: init_zero_er == 1,
          net_weight?: net_w == 1,
          gross_weight?: net_w == 0,
          high_range?: range == 3,
          low_range?: range == 0
        }

      <<
        3::4,
        eeprom_er::1,
        ram_er::1,
        zero::1,
        motion::1,
        3::4,
        calibr_er::1,
        rom_er::1,
        over_cap::1,
        under_cap::1
      >> ->
        %{
          eeprom_error?: eeprom_er == 1,
          ram_error?: ram_er == 1,
          zero?: zero == 1,
          in_motion?: motion == 1,
          calibration_error?: calibr_er == 1,
          rom_error?: rom_er == 1,
          over_capacity?: over_cap == 1,
          under_capacity?: under_cap == 1
        }
    end
  end
end
