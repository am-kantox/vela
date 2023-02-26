defmodule WeatherForecast do
  @moduledoc """
  The example of `Vela` implementation, demontrating the real-life
  module using `Vela` for timeseries control. 
  """

  use Boundary, deps: [Vela]

  alias WeatherForecast, as: Me

  use Vela,
    __globals__: [validator: Me],
    tomorrow: [limit: 5, errors: 1],
    two_days: [limit: 3],
    week: [limit: 2, sorter: &Me.sort/2]

  @behaviour Vela.Validator

  @impl Vela.Validator
  def valid?(_serie, value), do: value > 0

  @doc "Sort function to be used as `:sorter` in series"
  def sort(v1, v2), do: v1 <= v2
end
