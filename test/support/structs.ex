defmodule Test.Vela.Struct do
  use Vela,
    series1: [limit: 3, validator: Test.Vela.Struct, errors: 1],
    series2: [limit: 2, validator: {Test.Vela.Struct, :valid_2?}]

  @behaviour Vela.Validator

  @impl Vela.Validator
  def valid?(%__MODULE__{} = _state, _key, value) do
    value > 0
  end

  def valid_2?(%__MODULE__{} = _state, _key, value) do
    value < 0
  end
end
