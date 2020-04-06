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
        def pop(%_type{unquote(key) => [value | tail]} = data, unquote(key)),
          do: {value, %{data | unquote(key) => tail}}

        @impl Elixir.Access
        def pop(%_{} = data, _), do: {nil, data}

        @impl Elixir.Access
        def get_and_update(%_type{unquote(key) => values} = data, unquote(key), fun) do
          case fun.(List.first(values)) do
            :pop ->
              pop(data, unquote(key))

            {get_value, update_value} ->
              validator = Keyword.get(@opts[unquote(key)], :validator, fn _, _, _ -> true end)

              valid =
                case validator do
                  f when is_function(f, 3) -> f.(data, unquote(key), update_value)
                  m when is_atom(m) -> m.valid?(data, unquote(key), update_value)
                end

              updated_data =
                if valid do
                  history_limit = Keyword.get(@opts[unquote(key)], :limit, @history_limit)
                  values = Enum.take([update_value | values], history_limit)

                  %{data | unquote(key) => values}
                else
                  error_limit = Keyword.get(@opts[unquote(key)], :errors, @error_limit)

                  errors =
                    Map.update(
                      data.__errors__,
                      unquote(key),
                      [update_value],
                      &Enum.take([update_value | &1], error_limit)
                    )

                  %{data | __errors__: errors}
                end

              {get_value, updated_data}
          end
        end

        @impl Elixir.Access
        def get_and_update(%_{} = data, _, _), do: {nil, data}
      end)
    end
  end
end
