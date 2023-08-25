defmodule NCITest do
  use ExUnit.Case, async: true

  alias Chat.Sync.Weigh.NCI

  @response_charlist [10, 32, 32, 32, 32, 48, 46, 56, 107, 103, 13, 10, 48, 112, 48, 13, 3]
  @correct_weight "0.8kg"
  @correct_status_binary "0p0"
  @correct_status_map %{
    calibration_error?: false,
    eeprom_error?: false,
    gross_weight?: true,
    high_range?: false,
    in_motion?: false,
    init_zero_error?: false,
    low_range?: true,
    net_weight?: false,
    over_capacity?: false,
    ram_error?: false,
    rom_error?: false,
    under_capacity?: false,
    zero?: false
  }

  test "NCI proto should parse correct" do
    response = to_string(@response_charlist)

    assert {:ok, {@correct_weight, @correct_status_binary}} == NCI.parse_weight_response(response)
  end

  test "NCI should unwind status" do
    assert @correct_status_map == NCI.parse_status("0p0")
  end

  test "empty should return error" do
    assert {:error, :no_data} = NCI.parse_weight_response("")
  end
end
