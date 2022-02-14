defmodule Vela.Macros do
  @moduledoc false

  alias Vela.Stubs

  def make_arity_2(f) when is_function(f, 1),
    do: fn _serie, value -> f.(value) end

  def make_arity_2(f) when is_function(f, 2),
    do: f

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
    extra_types =
      Enum.map(extra_types, fn
        {k, nil} ->
          {k, [{{:., [], [{:__aliases__, [alias: false], [:Vela]}, :value]}, [], []}]}

        {k, type} when is_atom(type) ->
          {k, [{type, [], []}]}

        {k, {{_, _, _} = module, type}} ->
          {k, [{{:., [], [module, type]}, [], []}]}

        {k, {module, type}} when is_atom(module) and is_atom(type) ->
          modules = module |> Module.split() |> Enum.map(&:"#{&1}")
          {k, [{{:., [], [{:__aliases__, [alias: false], modules}, type]}, [], []}]}

        {k, v} ->
          {k, [v]}
      end)

    {:%{}, [],
     [
       {:__struct__, {:__MODULE__, [], Elixir}},
       {:__errors__,
        [
          {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :kv]}, [], []}
        ]},
       {:__meta__, {{:., [], [{:__aliases__, [alias: false], [:Access]}, :t]}, [], []}}
       | extra_types
     ]}
  end

  defmacro do_typedef(nil, opts) do
    quote bind_quoted: [opts: opts] do
      types = for {k, v} <- opts, do: {k, v[:type]}
      @type t :: unquote(use_types(types))
    end
  end

  defmacro do_typedef(typedef, _) do
    quote do
      @type t :: unquote(typedef)
    end
  end
end
