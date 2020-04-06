defmodule Vela do
  @moduledoc """
  `Vela` is a tiny library providing easy management of
  validated cached state with some history.

  Including `use Vela` in your module would turn the module
  into struct, setting field accordingly to the specification,
  passed as a parameter.

  `Vela` allows the following configurable parameters per field:

  - length of the series to keep (default `5`)
  - validation function as either module implementing `Vela.Validator`
    behaviour, or a local function (default `fn _, _, _ -> true end`)
  - timestamp extractor function to either extract the timestamp
    from the underlying terms (default `&DateTime.utc_now/0`)
  - number of errors to keep (default: `5`)

  `Vela` implements `Access` behaviour.

  ## Usage

      defmodule Vela.Test do
        use Vela,
          series1: [limit: 3, errors: 1], # no validation
          series2: [limit: 2, validator: Vela.Test]

        @behaviour Vela.Validator

        @impl Vela.Validator
        def valid?(%__MODULE__{} = state, key, value) do
          value > 0
        end
      end

  In the example above, before any structure update attempt
  (via `Access`,) this `valid?/3` function would be called.

  If it returns `true`, the value gets inserted / updated, and
  the series behind is truncated if needed. It it returns `false`,
  the state _is not updated_, and the value is put into the map
  under `__errors__` key of the struct. The length of errors
  is also configurable via `errors:` keyword parameter.
  """

  @typedoc "Represents the struct created by this behaviour module"
  @type t :: %{
          :__struct__ => atom(),
          :__errors__ => %{optional(atom) => [any()]},
          :__meta__ => keyword(),
          optional(atom()) => any()
        }

  @doc """
  Hello world.

  ## Examples

      iex> Vela.hello()
      :world

  """
  def hello do
    :world
  end
end
