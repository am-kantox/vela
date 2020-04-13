defmodule Test.Vela.Struct do
  @moduledoc false

  use Vela,
    series1: [limit: 3, validator: Test.Vela.Struct, errors: 1],
    series2: [limit: 2, validator: &Test.Vela.Struct.valid_2?/2]

  @behaviour Vela.Validator

  @impl Vela.Validator
  def valid?(_key, value) do
    value > 0
  end

  def valid_2?(_key, value) do
    value < 0
  end
end
