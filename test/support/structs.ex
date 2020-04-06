defmodule Test.Vela.Struct do
  use Vela,
    series1: [limit: 3, errors: 1],
    series2: [limit: 2, validator: Vela.Test]

  @behaviour Vela.Validator

  @impl Vela.Validator
  def valid?(%__MODULE__{} = _state, _key, value) do
    value > 0
  end
end
