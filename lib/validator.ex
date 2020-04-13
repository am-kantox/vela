defmodule Vela.Validator do
  @moduledoc """
  The validator behaviour, implementations are used by `Vela`
  to validate new values to be inserted into the state.
  """

  @doc """
  When implemented, the module might be passed as validator to `use Vela`
  """
  @callback valid?(key :: term(), value :: any()) :: boolean()
end
