defmodule Test.Vela.Struct do
  @moduledoc false

  alias Vela.Validator
  alias Test.Vela.Struct, as: Me

  use Vela,
    series1: [limit: 3, validator: Me, errors: 1],
    series2: [limit: 2, validator: &Me.valid_2?/2]

  @behaviour Validator

  @impl Validator
  def valid?(_key, value) do
    value > 0
  end

  def valid_2?(_key, value) do
    value < 0
  end
end
