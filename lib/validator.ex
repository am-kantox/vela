defmodule Vela.Validator do
  @moduledoc """
  The validator behaviour, implementations are used by `Vela`
  to validate new values to be inserted into the state.
  """
  @callback valid?(vela :: Vela.t(), key :: term(), value :: any()) :: boolean()
end
