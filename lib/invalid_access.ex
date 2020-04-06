defmodule Vela.AccessError do
  @moduledoc """
  The generic exception thrown when the access in invalid.

  Parameters:

  - `source` the source of the exception
  - `field` the field the access to has failed
  """
  defexception [:message, :source, :field]

  @impl true
  def exception(opts) do
    source =
      case Keyword.get(opts, :source, "N/A") do
        %type{} -> type
        s when is_binary(s) -> s
        other -> inspect(other)
      end

    field = opts |> Keyword.get(:field, "N/A") |> inspect()
    message = "Invalid access attempt. Field #{field} is not available on #{source}."

    %Vela.AccessError{source: source, field: field, message: message}
  end
end
