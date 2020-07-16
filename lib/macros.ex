defmodule Vela.Macros do
  @moduledoc false

  alias Vela.Stubs

  defmacro use_config(opts) do
    quote do
      Enum.map(unquote(opts), fn {serie, vela} ->
        vela =
          vela
          |> Keyword.put_new(:sorter, &Stubs.sort/2)
          |> Keyword.put_new(:compare_by, &Stubs.itself/1)
          |> Keyword.put_new(:comparator, &Stubs.compare/2)
          |> Keyword.put_new(:corrector, &Stubs.correct/3)
          |> Keyword.put_new(:threshold, nil)
          |> Keyword.update(:validator, &Stubs.validate/1, fn existing ->
            case existing do
              fun when is_function(fun, 1) or is_function(fun, 2) -> fun
              m when is_atom(m) -> &m.valid?/2
              other -> raise Vela.AccessError, field: :validator
            end
          end)

        {serie, vela}
      end)
    end
  end

  def use_types(extra_types) when is_list(extra_types) do
    {:%{}, [],
     [
       {:__struct__, {:__MODULE__, [], Elixir}},
       {:__errors__,
        [
          {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :kv]}, [], []}
        ]},
       {:__meta__, {:keyword, [], []}}
       | extra_types
     ]}
  end

  defmacro main_ast do
    quote do
      @doc "Returns the list of series declared on #{__MODULE__}"
      @spec series :: [Vela.serie()]
      def series, do: @fields_ordered

      @doc "Returns the config #{__MODULE__} was declared with"
      @spec config :: [{atom(), Vela.options()}]
      def config, do: @config

      @doc "Returns the config for the serie `serie`, #{__MODULE__} was declared with"
      @spec config(Vela.serie()) :: Vela.options()
      def config(serie), do: @config[serie]

      @doc "Returns the config value for the serie `serie`, #{__MODULE__} was declared with, and key"
      @spec config(Vela.serie(), key :: atom(), default :: any()) :: Vela.option()
      def config(serie, key, default \\ nil), do: Keyword.get(@config[serie], key, default)

      use Vela.Access, @config
      @behaviour Vela

      @impl Vela
      def slice(vela),
        do: for({serie, [h | _]} <- vela, do: {serie, h})

      @impl Vela
      def purge(%__MODULE__{} = vela, validator \\ nil),
        do: Vela.purge(vela, validator)

      @impl Vela
      def delta(%__MODULE__{} = vela, comparator \\ nil),
        do: Vela.δ(vela, comparator)

      @impl Vela
      def equal?(%__MODULE__{} = v1, %__MODULE__{} = v2),
        do: Vela.equal?(v1, v2)
    end
  end

  defmacro wrapped_use(opts) when is_list(opts) do
    fields = Keyword.keys(opts)

    {meta, opts} = Keyword.pop(opts, :mη, [])

    typedefs =
      for {serie, desc} <- opts do
        {
          serie,
          Keyword.get(desc, :type, [
            {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :value]}, [], []}
          ])
        }
      end

    typedef =
      Macro.escape(
        {:%{}, [],
         [
           {:__struct__, {:__MODULE__, [], Elixir}},
           {:__errors__,
            [
              {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :kv]}, [], []}
            ]},
           {:__meta__, {:keyword, [], []}}
           | typedefs
         ]}
      )

    opts = for {serie, desc} <- opts, do: {serie, Keyword.delete(desc, :type)}

    quote generated: true, location: :keep do
      {unquote(opts), unquote(meta), unquote(fields), unquote(typedef)}
    end
  end

  defmacro wrapped_use(opts) do
    quote generated: true,
          location: :keep,
          bind_quoted: [opts: opts] do
      {meta, opts} = Keyword.pop(opts, :mη, [])
      fields = Keyword.keys(opts)

      {opts, meta, fields,
       use_types(
         Enum.zip(
           fields,
           Stream.cycle([[{{:., [], [{:__aliases__, [alias: false], [:Vela]}, :value]}, [], []}]])
         )
       )}
    end
  end
end
