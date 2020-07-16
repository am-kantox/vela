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
  - `corrector` — the function to be used to correct the values rejected by `validator`;
    the function should return `{:ok, corrected_value}` to enforce insertion into `Vela`,
    or `:error` if the value cannot be corrected and should be nevertheless rejected
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

  @typedoc """
  The type of validator function to be passed as `:validator` keyword parameter
    to the series.
  """
  @type validator :: (value() -> boolean()) | (serie(), value() -> boolean())

  @typedoc """
  The type of comparator function to be passed as `:comparator` keyword parameter
    to the series.
  """
  @type comparator :: (value(), value() -> boolean())

  @typedoc """
  The type of sorter function to be passed as `:sorter` keyword parameter
    to the series.
  """
  @type sorter :: (value(), value() -> boolean())

  @typedoc """
  The type of sorter function to be passed as `:sorter` keyword parameter
    to the series.
  """
  @type corrector :: (t(), serie(), value() -> {:ok, value()} | :error)

  @typedoc "Represents the struct created by this behaviour module"
  @type t :: %{
          :__struct__ => atom(),
          :__errors__ => [kv()],
          :__meta__ => keyword(),
          optional(serie()) => [value()]
        }

  @typedoc "Options allowed in series configuration"
  @type option ::
          {:limit, non_neg_integer()}
          | {:type, any()}
          | {:initial, [term()]}
          | {:compare_by, (value() -> any())}
          | {:comparator, comparator()}
          | {:threshold, number()}
          | {:validator, validator()}
          | {:sorter, sorter()}
          | {:corrector, corrector()}
          | {:errors, keyword()}

  @typedoc "Series configuration"
  @type options :: [option()]

  @doc """
  Returns a keyword with series as keys and the hottest value as a value

  _Example:_

  ```elixir
  defmodule AB do
    use Vela, a: [], b: []
  end
  AB.slice(struct(AB, [a: [1, 2], b: [3, 4]]))

  #⇒ [a: 1, b: 3]
  ```
  """
  @callback slice(t()) :: [kv()]

  @doc """
  Removes obsoleted elements from the series using the validator given as a second parameter,
    or a default validator for this serie.
  """
  @callback purge(t(), nil | validator()) :: t()

  @doc """
  Returns `{min, max}` tuple for each serie, using the comparator given as a second parameter,
    or a default comparator for this serie.
  """
  @callback delta(t(), nil | (serie(), value(), value() -> boolean())) :: [
              {atom(), {value(), value()}}
            ]

  @doc "Checks two velas given as an input for equality"
  @callback equal?(t(), t()) :: boolean()

  use Boundary, exports: [Access, AccessError, Stubs, Macros]

  alias Vela.Stubs
  import Vela.Macros
  @doc false
  defmacro __using__(opts) do
    quote generated: true, location: :keep do
      @compile {:inline, series: 0, config: 0, config: 1, config: 2}
      @after_compile {Vela, :implement_enumerable}

      import Vela.Macros

      {opts, meta, fields, typedef} = wrapped_use(unquote(opts))

      @meta meta
      @fields fields

      # @type t :: unquote(typedef)

      @config use_config(opts)
      @field_count Enum.count(@fields)
      fields_index = Enum.with_index(@fields)

      @fields_ordered Enum.sort(
                        @fields,
                        Keyword.get(meta, :order_by, &(fields_index[&1] <= fields_index[&2]))
                      )

      defstruct [
        {:__errors__, []},
        {:__meta__, meta}
        | Enum.zip(@fields_ordered, Stream.cycle([[]]))
      ]

      main_ast()
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

  @spec map(vela :: t(), (kv() -> kv())) :: t()
  @doc """
  Maps the series using `fun` and returns the new `Vela` instance with series mapped
  """
  def map(%mod{} = vela, fun) do
    mapped =
      vela
      |> Map.take(mod.series)
      |> Enum.map(fun)

    struct(vela, mapped)
  end

  @spec flat_map(vela :: t(), (kv() -> kv()) | (serie(), value() -> kv())) :: [kv()]
  @doc """
  Flat maps the series using `fun` and returns the keyword with
  duplicated keys and mapped values.

  _Example:_

  ```elixir
  defmodule EO do
    use Vela,
      even: [limit: 2],
      odd: [limit: 2]

    def flat_map(%EO{} = v),
      do: Vela.flat_map(v, & {&1, &2+1})
  end
  EO.flat_map(struct(EO, [even: [2, 4], odd: [1, 3]]))

  #⇒ [even: 3, even: 5, odd: 2, odd: 4]
  ```

  """
  def flat_map(vela, fun \\ & &1)

  def flat_map(%mod{} = vela, fun) when is_function(fun, 2) do
    for {serie, list} <- Map.take(vela, mod.series()),
        value <- list,
        do: fun.(serie, value)
  end

  def flat_map(%_mod{} = vela, fun) when is_function(fun, 1),
    do: flat_map(vela, &fun.({&1, &2}))

  @spec validator!(data :: t(), serie :: serie()) :: validator()
  @doc false
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
  @doc """
  Returns `{min, max}` tuple for each serie, using the comparator given as a second parameter,
    or a default comparator for each serie.
  """
  @doc since: "0.7.0"
  def δ(%type{} = vela, comparator \\ nil) do
    for {serie, list} <- vela,
        serie in type.series(),
        {compare_by, comparator} =
          if(is_nil(comparator),
            do: {type.config(serie, :compare_by), type.config(serie, :comparator)},
            else: {&Stubs.itself/1, comparator}
          ) do
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

  @spec purge(vela :: t(), validator :: nil | validator()) :: t()
  @doc false
  @doc since: "0.9.2"
  def purge(%type{} = vela, validator \\ nil) do
    purged =
      for {serie, list} <- vela,
          serie in type.series(),
          validator = if(is_nil(validator), do: Vela.validator!(vela, serie), else: validator),
          do: {serie, Enum.filter(list, &validator.(serie, &1))}

    struct(vela, purged)
  end

  @spec put(vela :: t(), serie :: serie(), value :: value()) :: t()
  @doc """
  Inserts the new value into the serie, going through all the validation and sorting.

  If the value has not passed validation, it’s put into `:__errors__` internal list.
  If the new length of the serie exceeds the limit set for this serie, the last value
  (after sorting) gets discarded.
  """
  def put(%_{} = vela, serie, value),
    do: put_in(vela, [serie], value)

  @spec equal?(v1 :: t(), v2 :: t()) :: boolean()
  @doc false
  @doc since: "0.9.2"
  def equal?(%type{} = v1, %type{} = v2) do
    [v1, v2]
    |> Enum.map(&Vela.flat_map/1)
    |> Enum.reduce(&do_equal?/2)
  end

  def equal?(_, _), do: false

  @spec do_equal?(kw1 :: [Vela.kv()], kw2 :: [Vela.kv()]) :: boolean()
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

  @spec within_threshold?({value(), value()}, nil | number(), (value() -> number())) ::
          validator()
  defp within_threshold?(_minmax, nil, _compare_by), do: fn _ -> true end
  defp within_threshold?({nil, nil}, _threshold, _compare_by), do: fn _ -> true end

  defp within_threshold?({min, max}, threshold, compare_by) do
    [min, max] = Enum.map([min, max], compare_by)
    band = max - min
    &(compare_by.(&1) >= min - band * threshold && compare_by.(&1) <= max + band * threshold)
  end

  defmodule Stubs do
    @moduledoc false
    @spec itself(Vela.value()) :: Vela.value()
    def itself(v), do: v

    @spec validate(Vela.value()) :: boolean()
    def validate(_value), do: true

    @spec compare(Vela.value(), Vela.value()) :: boolean()
    def compare(v1, v2), do: v1 < v2

    @spec sort(Vela.value(), Vela.value()) :: boolean()
    def sort(_v1, _v2), do: true

    @spec correct(Vela.t(), Vela.serie(), Vela.value()) :: {:ok, Vela.value()} | :error
    def correct(_vela, _serie, _value), do: :error
  end
end
