defmodule Test.Vela.Struct do
  @moduledoc false

  use Boundary, deps: [Vela]

  alias Test.Vela.Struct, as: Me
  alias Vela.Validator

  use Vela,
    series1: [limit: 3, validator: Me, errors: 1],
    series2: [limit: 2, validator: &Me.valid_2?/2],
    series3: [limit: 2, sorter: &Me.sort/2]

  @behaviour Validator

  @impl Validator
  def valid?(_serie, value), do: value > 0

  def valid_2?(_serie, value), do: value < 0

  def sort(v1, v2), do: v1 <= v2
end

defmodule Test.Vela.Struct2Checkers do
  @moduledoc false

  use Boundary

  def good_integer(int) when is_integer(int), do: true
  def good_integer(_), do: false

  def good_date(:dates, %Date{}), do: true
  def good_date(_, _), do: false

  def compare_dates(%Date{} = d1, %Date{} = d2),
    do: Date.compare(d1, d2) == :lt

  def compare_maps(%{date: d1}, %{date: d2}),
    do: Date.compare(d1, d2) == :lt

  def extract_number(%{number: number}), do: number
end

defmodule Test.Vela.Struct2 do
  @moduledoc false

  use Boundary, deps: [Vela, Test.Vela.Struct2Checkers]

  import Test.Vela.Struct2Checkers

  use Vela,
    integers: [limit: 3, validator: &good_integer/1, sorter: &</2, threshold: 0.5],
    dates: [
      limit: 3,
      validator: &good_date/2,
      sorter: &compare_dates/2,
      comparator: &compare_dates/2
    ],
    maps: [limit: 3, compare_by: &extract_number/1, sorter: &compare_maps/2, threshold: 0.5]
end
