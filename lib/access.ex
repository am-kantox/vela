defmodule Vela.Access do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @history_limit Application.get_env(:vela, :history_limit, 5)
      @error_limit Application.get_env(:vela, :error_limit, 5)

      @behaviour Elixir.Access

      Enum.each(Keyword.keys(opts), fn key ->
        opts = Macro.escape(opts)

        @impl Elixir.Access
        def fetch(%_{unquote(key) => [value | _]}, unquote(key)),
          do: {:ok, value}

        @impl Elixir.Access
        def pop(%_type{unquote(key) => []} = data, unquote(key)),
          do: {nil, data}

        @impl Elixir.Access
        def pop(%_type{unquote(key) => [value | tail]} = data, unquote(key)),
          do: {value, %{data | unquote(key) => tail}}

        @impl Elixir.Access
        def get_and_update(%type{unquote(key) => values} = data, unquote(key), fun) do
          case fun.(List.first(values)) do
            :pop ->
              pop(data, unquote(key))

            {get_value, update_value} ->
              {valid, update_value} =
                if Vela.validator!(data, unquote(key)).(update_value) do
                  {true, update_value}
                else
                  case type.config(unquote(key))[:corrector].(data, unquote(key), update_value) do
                    {:ok, corrected_value} -> {true, corrected_value}
                    :error -> {false, update_value}
                  end
                end

              updated_data =
                if valid do
                  sorter = Keyword.get(unquote(opts)[unquote(key)], :sorter)

                  values =
                    Enum.take(
                      Enum.sort([update_value | values], sorter),
                      Keyword.get(unquote(opts)[unquote(key)], :limit, @history_limit)
                    )

                  %{data | unquote(key) => values}
                else
                  errors =
                    Enum.take(
                      [{unquote(key), update_value} | data.__errors__],
                      Keyword.get(unquote(opts)[unquote(key)], :errors, @error_limit)
                    )

                  %{data | __errors__: errors}
                end

              {get_value, updated_data}
          end
        end
      end)

      @impl Elixir.Access
      def fetch(%_{}, _), do: :error

      @impl Elixir.Access
      def pop(%_{} = data, key),
        do: raise(Vela.AccessError, source: __MODULE__, field: key)

      @impl Elixir.Access
      def get_and_update(%_{} = data, key, _),
        do: raise(Vela.AccessError, source: __MODULE__, field: key)
    end
  end
end
