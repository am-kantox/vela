defmodule Vela do
  @moduledoc """
  `Vela` is a tiny library providing easy management of
  validated cached state with some history.

  Including `use Vela` in your module would turn the module
  into struct, setting field accordingly to the specification,
  passed as a parameter.

  `Vela` allows the following configurable parameters per field:

  - `limit` — length of the series to keep (default: `5`)
  - `compare_by` — comparator extraction function to extract the value, to be used for
    comparison, from the underlying terms (default: `& &1`)
  - `comparator` — the function that accepts a series name and two values and returns
    the greater one to be used in `Vela.δ/1` (default: `&</2`)
  - `threshold` — if specified, the inserted value is checked to fit in `δ ± threshold`;
    whether it does not, it goes to `errors` (`float() | nil`, default: `nil`)
  - `validator` — the function to be used to invalidate the accumulated values (default:
    `fn _ -> true end`)
  - `sorter` — the function to be used to sort values within one serie, if
    none is given, it sorts in the natural order, FIFO, newest is the one to `pop`
  - `errors` — number of errors to keep (default: `5`)

  Also, Vela accepts `:mη` keyword parameter for the cases when the consumer needs
  the very custom meta to be passed to the struct.

  `Vela` implements `Access` behaviour.

  ## Usage

      defmodule Vela.Test do
        use Vela,
          series1: [limit: 3, errors: 1], # no validation
          series2: [limit: 2, validator: Vela.Test]
          series3: [
                compare_by: &Vela.Test.comparator/1,
                validator: &Vela.Test.validator/2
          ]

        @behaviour Vela.Validator

        @impl Vela.Validator
        def valid?(_serie, value), do: value > 0

        @spec comparator(%{created_at :: DateTime.t()}) :: DateTime.t()
        def comparator(%{created_at: created_at}),
          do: created_at

        @spec validator(value :: t()) :: boolean()
        def validator(value),
          do: is_integer(value) and value > 300
      end

  In the example above, before any structure update attempt
  (via `Access`,) this `valid?/2` function would be called.

  If it returns `true`, the value gets inserted / updated, and
  the series behind is truncated if needed. It it returns `false`,
  the state _is not updated_, and the value is put into the map
  under `__errors__` key of the struct. The length of errors
  is also configurable via `errors:` keyword parameter.
  """

  @typedoc "Represents a key in the Vela structure"
  @type serie :: atom()

  @typedoc "Represents a value in the Vela structure"
  @type value :: any()

  @typedoc "Represents a key-value pair in errors and unmatched"
  @type kv :: {serie(), value()}

  @typedoc "Represents the struct created by this behaviour module"
  @type t :: %{
          :__struct__ => atom(),
          :__errors__ => [kv()],
          :__meta__ => keyword(),
          optional(serie()) => [value()]
        }

  @doc "Returns a keyword with series as keys and the hottest value as a value"
  @callback slice(t()) :: [kv()]
  @doc """
  Removes obsoleted elements from the series using the validator given as a second parameter,
    or a default validator for this serie.
  """
  @callback purge(t(), nil | (serie(), value() -> boolean())) :: t()
  @doc """
  Returns `{min, max}` tuple for each serie, using the comparator given as a second parameter,
    or a default comparator for this serie.
  """
  @callback delta(t(), nil | (serie(), value(), value() -> boolean())) :: [
              {atom(), {value(), value()}}
            ]
  @doc "Checks two velas given as an input for equality"
  @callback equal?(t(), t()) :: boolean()

  use Boundary, exports: [Access, AccessError, Stubs]

  @doc false
  defmacro __using__(opts) do
    quote generated: true, location: :keep, bind_quoted: [opts: opts] do
      @compile {:inline, series: 0}

      {meta, opts} = Keyword.pop(opts, :mη, [])

      @after_compile {Vela, :implement_enumerable}

      @config Enum.map(opts, fn {serie, vela} ->
                vela =
                  vela
                  |> Keyword.put_new(:sorter, &Vela.Stubs.sort/2)
                  |> Keyword.put_new(:compare_by, &Vela.Stubs.itself/1)
                  |> Keyword.put_new(:comparator, &Vela.Stubs.compare/2)
                  |> Keyword.put_new(:threshold, nil)
                  |> Keyword.update(:validator, &Vela.Stubs.validate/1, fn existing ->
                    case existing do
                      fun when is_function(fun, 1) or is_function(fun, 2) -> fun
                      m when is_atom(m) -> &m.valid?/2
                      other -> raise Vela.AccessError, field: :validator
                    end
                  end)

                {serie, vela}
              end)

      @fields Keyword.keys(@config)
      @field_count Enum.count(@fields)

      fields_type =
        {:%{}, [],
         [
           {:__struct__, {:__MODULE__, [], Elixir}},
           {:__errors__,
            [
              {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :kv]}, [], []}
            ]},
           {:__meta__, {:keyword, [], []}}
           | Enum.zip(
               @fields,
               Stream.cycle([
                 [
                   {{:., [], [{:__aliases__, [alias: false], [:Vela]}, :value]}, [], []}
                 ]
               ])
             )
         ]}

      Enum.each([fields_type], fn ast ->
        @type t :: unquote(ast)
      end)

      fields_index = Enum.with_index(@fields)

      @fields_ordered Enum.sort(
                        @fields,
                        Keyword.get(meta, :order_by, &(fields_index[&1] <= fields_index[&2]))
                      )

      @with_initials [
        {:__errors__, []},
        {:__meta__, meta}
        | Enum.zip(@fields_ordered, Stream.cycle([[]]))
      ]

      defstruct @with_initials

      @doc false
      @spec series :: [Vela.serie()]
      def series, do: @fields_ordered

      @doc false
      @spec config :: keyword()
      def config, do: @config

      @doc false
      @spec config(Vela.serie()) :: any()
      def config(serie), do: @config[serie]

      use Vela.Access, @config
      @behaviour Vela

      @impl Vela
      def slice(vela),
        do: for({serie, [h | _]} <- vela, do: {serie, h})

      @impl Vela
      def purge(vela, validator \\ nil)

      def purge(%__MODULE__{} = vela, nil) do
        purged =
          for {serie, list} <- vela,
              serie in series(),
              do: {serie, Enum.filter(list, Vela.validator!(vela, serie))}

        struct(vela, purged)
      end

      def purge(%__MODULE__{} = vela, validator) do
        purged =
          for {serie, list} <- vela,
              serie in series(),
              do: {serie, Enum.filter(list, &validator.(serie, &1))}

        struct(vela, purged)
      end

      @impl Vela
      def delta(vela, comparator \\ nil)

      def delta(%__MODULE__{} = vela, nil) do
        for {serie, list} <- vela,
            serie in series(),
            compare_by = Keyword.get(@config[serie], :compare_by),
            comparator = Keyword.get(@config[serie], :comparator) do
          min_max =
            Enum.reduce(list, {nil, nil}, fn
              v, {nil, nil} ->
                {v, v}

              v, {min, max} ->
                {
                  if(comparator.(compare_by.(v), compare_by.(min)), do: v, else: min),
                  if(comparator.(compare_by.(max), compare_by.(v)), do: v, else: max)
                }
            end)

          {serie, min_max}
        end
      end

      def delta(%__MODULE__{} = vela, comparator) do
        for {serie, list} <- vela, serie in series() do
          min_max =
            Enum.reduce(list, {nil, nil}, fn
              v, {nil, nil} ->
                {v, v}

              v, {min, max} ->
                {
                  if(comparator.(serie, v, min), do: v, else: min),
                  if(comparator.(serie, max, v), do: v, else: max)
                }
            end)

          {serie, min_max}
        end
      end

      @impl Vela
      def equal?(%__MODULE__{} = v1, %__MODULE__{} = v2) do
        [v1, v2]
        |> Enum.map(&Vela.flat_map/1)
        |> Enum.reduce(&do_equal?/2)
      end

      @spec do_equal?(kw1 :: keyword(), kw2 :: keyword()) :: boolean()
      defp do_equal?(kw1, kw2) when length(kw1) != length(kw2), do: false

      defp do_equal?(kw1, kw2) do
        [kw1, kw2]
        |> Enum.zip()
        |> Enum.reduce_while(true, fn
          {{serie, %mod{} = value1}, {serie, %mod{} = value2}}, true ->
            if (mod.__info__(:functions)[:equal?] == 2 and mod.equal?(value1, value2)) or
                 (mod.__info__(:functions)[:compare] == 2 and mod.compare(value1, value2) == :eq) or
                 value1 == value2,
               do: {:cont, true},
               else: {:halt, false}

          {{serie, value1}, {serie, value2}}, true ->
            if value1 == value2, do: {:cont, true}, else: {:halt, false}

          _, true ->
            {:halt, false}
        end)
      end
    end
  end

  defmacrop do_implement_enumerable(module) do
    quote location: :keep, bind_quoted: [module: module] do
      defimpl Enumerable, for: module do
        @moduledoc false

        @module module
        @fields @module.series()
        @field_count Enum.count(@fields)

        def count(%@module{} = vela), do: {:ok, @field_count}

        Enum.each(@fields, fn field ->
          def member?(%@module{} = vela, unquote(field)), do: {:ok, true}
        end)

        def member?(%@module{} = vela, _), do: {:ok, false}

        def reduce(vela, state_acc, fun, inner_acc \\ @fields)

        def reduce(%@module{} = vela, {:halt, acc}, _fun, _inner_acc),
          do: {:halted, acc}

        def reduce(%@module{} = vela, {:suspend, acc}, fun, inner_acc),
          do: {:suspended, acc, &reduce(vela, &1, fun, inner_acc)}

        def reduce(%@module{} = vela, {:cont, acc}, _fun, []),
          do: {:done, acc}

        Enum.each(@fields, fn field ->
          def reduce(%@module{unquote(field) => list} = vela, {:cont, acc}, fun, [
                unquote(field) | tail
              ]),
              do: reduce(vela, fun.({unquote(field), list}, acc), fun, tail)
        end)

        def slice(%@module{}), do: {:error, @module}
      end
    end
  end

  @doc false
  def implement_enumerable(%Macro.Env{module: module}, _bytecode),
    do: do_implement_enumerable(module)

  @spec map(vela :: t(), ({serie(), value()} -> {serie(), value()})) :: t()
  def map(%_{} = vela, fun),
    do: struct(vela, Enum.map(vela, fun))

  @spec flat_map(vela :: t(), ({serie(), value()} -> {serie(), value()})) :: list()
  def flat_map(%mod{} = vela, fun \\ & &1),
    do:
      for(
        {serie, list} <- vela,
        serie in mod.series(),
        value <- list,
        do: fun.({serie, value})
      )

  @spec validator!(data :: Vela.t(), serie :: atom()) :: (Vela.value() -> boolean())
  def validator!(%type{} = data, serie) do
    validator = type.config(serie)[:validator]
    compare_by = type.config(serie)[:compare_by]

    within_threshold =
      within_threshold?(Vela.δ(data)[serie], type.config(serie)[:threshold], compare_by)

    case validator do
      f when is_function(f, 1) ->
        fn value ->
          within_threshold.(value) && validator.(value)
        end

      f when is_function(f, 2) ->
        fn value ->
          within_threshold.(value) && validator.(serie, value)
        end

      _other ->
        raise Vela.AccessError, field: :validator, source: &__MODULE__.validator!/2
    end
  end

  @spec δ(t(), nil | (serie(), value(), value() -> boolean())) ::
          [{atom(), {value(), value()}}]
  def δ(%type{} = vela, comparator \\ nil), do: type.delta(vela, comparator)

  @spec within_threshold?({number(), number()}, nil | number(), (Vela.value() -> boolean())) ::
          (Vela.value() -> boolean())
  defp within_threshold?(_minmax, nil, _compare_by), do: fn _ -> true end
  defp within_threshold?({nil, nil}, _threshold, _compare_by), do: fn _ -> true end

  defp within_threshold?({min, max}, threshold, compare_by) do
    [min, max] = Enum.map([min, max], compare_by)
    band = max - min
    &(compare_by.(&1) >= min - band * threshold && compare_by.(&1) <= max + band * threshold)
  end

  defmodule Stubs do
    @moduledoc false
    @spec itself(Vela.value()) :: any()
    def itself(v), do: v

    @spec validate(Vela.value()) :: boolean()
    def validate(_value), do: true

    @spec compare(Vela.value(), Vela.value()) :: boolean()
    def compare(v1, v2), do: v1 < v2

    @spec sort(Vela.value(), Vela.value()) :: boolean()
    def sort(_v1, _v2), do: true
  end
end
