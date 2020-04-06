defmodule Vela.Access do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @opts opts

      @history_limit Application.get_env(:vela, :history_limit, 5)
      @error_limit Application.get_env(:vela, :error_limit, 5)

      @behaviour Elixir.Access

      Enum.each(Keyword.keys(@opts), fn key ->
        @impl Elixir.Access
        def fetch(%_{unquote(key) => [value | _]}, unquote(key)),
          do: {:ok, value}

        @impl Elixir.Access
        def fetch(%_{}, _), do: :error

        @impl Elixir.Access
        def pop(%type{unquote(key) => [value | tail]} = data, unquote(key)),
          do: {value, %type{data | unquote(key) => tail}}

        @impl Elixir.Access
        def pop(%_{} = data, _), do: {nil, data}

        @impl Elixir.Access
        def get_and_update(%type{unquote(key) => [value | _] = values} = data, unquote(key), fun) do
          case fun.(value) do
            :pop ->
              pop(data, unquote(key))

            {get_value, update_value} ->
              updated_data =
                if validator.valid?(data, unquote(key), update_value) do
                  history_limit = Keyword.get(@opts[unquote(key)], :limit, @history_limit)
                  values = Enum.take([update_value | values], history_limit)
                  %type{data | unquote(key) => values}
                else
                  error_limit = Keyword.get(@opts[unquote(key)], :errors, @error_limit)

                  errors =
                    Map.update(
                      data.__errors__,
                      unquote(key),
                      [update_value],
                      &Enum.take([update_value | &1], error_limit)
                    )

                  %type{data | __errors__: errors}
                end

              {get_value, data}
          end
        end
      end)
    end
  end
end
