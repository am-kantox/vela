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

  Also, Vela accepts `:__meta__` keyword parameter for the cases when the consumer needs
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

  @typedoc "Represents the internal state aka per-vela property container"
  @type state :: Access.t()

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
          :__meta__ => state(),
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

      iex> defmodule AB do
      ...>   use Vela, a: [], b: [], c: []
      ...> end
      ...> AB.slice(struct(AB, [a: [1, 2], b: [3], c: []]))
      [a: 1, b: 3]
  """
  @callback slice(vela :: t()) :: [kv()]

  @doc """
  Returns a keyword with series as keys and the average value as a value

  _Example:_

      iex> defmodule XY do
      ...>   use Vela, x: [], y: []
      ...> end
      ...> XY.average(struct(XY, x: [1, 2, 3], y: [5, 7, 9]), &(Enum.sum(&1) / length(&1)))
      [x: 2.0, y: 7.0]
      ...> defmodule Averager do
      ...>   def average(values), do: Enum.sum(values) / length(values)
      ...> end
      ...> XY.average(struct(XY, x: [1, 2, 3], y: [5, 7, 9]), Averager)
      [x: 2.0, y: 7.0]
  """
  @doc since: "0.14.0"
  @callback average(vela :: t(), averager :: ([value()] -> value()) | module()) :: [kv()]

  @doc """
  Removes obsoleted elements from the series using the validator given as a second parameter,
    or a default validator for this serie.
  """
  @callback purge(vela :: t(), validator :: nil | validator()) :: t()

  @doc """
  Returns `{min, max}` tuple for each serie, using the comparator given as a second parameter,
    or a default comparator for this serie.
  """
  @callback delta(vela :: t(), comparator :: nil | (serie(), value(), value() -> boolean())) :: [
              {atom(), {value(), value()}}
            ]

  @doc "Checks two velas given as an input for equality"
  @callback equal?(vela1 :: t(), vela2 :: t()) :: boolean()

  use Boundary, exports: [Access, AccessError, Stubs, Macros, Validator]

  alias Vela.Stubs
  import Vela.Macros

  @doc false
  def do_def_using(module \\ nil, opts \\ nil, typedef \\ nil) do
    quote generated: true, location: :keep do
      @me unquote(module) || __MODULE__

      @compile {:inline, series: 0, config: 0, config: 1, config: 2}
      @after_compile {Vela, :implement_enumerable}

      import Vela.Macros

      opts = unquote(opts) || @__opts__

      do_typedef(unquote(typedef), opts)

      {meta, opts} = Keyword.pop(opts, :__meta__, [])
      @meta Keyword.put_new(meta, :state, [])

      @config use_config(opts)

      @fields Keyword.keys(opts)
      @field_count Enum.count(@fields)
      fields_index = Enum.with_index(@fields)

      @fields_ordered Enum.sort(
                        @fields,
                        Keyword.get(@meta, :order_by, &(fields_index[&1] <= fields_index[&2]))
                      )

      defstruct [
        {:__errors__, []},
        {:__meta__, @meta}
        | Enum.zip(@fields_ordered, Stream.cycle([[]]))
      ]

      @doc "Returns the initial state of `#{@me}`, custom options etc"
      @spec state(Vela.t()) :: Vela.state()
      def state(%@me{__meta__: meta}), do: get_in(meta, [:state])

      @doc false
      @spec update_meta(Vela.t(), [atom()], (any() -> any())) :: Vela.t()
      def update_meta(%@me{__meta__: meta} = vela, path, fun) when is_function(fun, 1),
        do: %@me{__meta__: update_in(meta, path, fun)}

      @doc "Updates the internal state of `#{@me}`"
      @spec update_state(Vela.t(), (Vela.state() -> Vela.state())) :: Vela.t()
      def update_state(%@me{} = vela, fun) when is_function(fun, 1),
        do: update_meta(vela, [:state], fun)

      @doc "Returns the list of series declared on `#{@me}`"
      @spec series :: [Vela.serie()]
      def series, do: @fields_ordered

      @doc "Returns the config `#{@me}` was declared with"
      @spec config :: [{atom(), Vela.options()}]
      def config, do: @config

      @doc false
      @spec config(Vela.serie()) :: Vela.options()
      def config(serie), do: @config[serie]

      @doc false
      @spec config(Vela.serie(), key :: atom(), default :: any()) :: Vela.option()
      def config(serie, key, default \\ nil)

      def config(serie, key, %@me{__meta__: meta}) do
        get_in(meta, [serie, key]) ||
          Keyword.get_lazy(meta, key, fn ->
            get_in(meta, [:state, serie, key]) ||
              get_in(meta, [:state, key]) ||
              @config[serie][key]
          end)
      end

      def config(serie, key, default), do: Keyword.get(@config[serie], key, default)

      use Vela.Access, @config
      @behaviour Vela

      @impl Vela
      @doc """
      Implementation of `c:Vela.slice/1`.

      Returns a slice of all series as `keyword()` in format `{Vela.serie(), Vela.value()}`,
      if the series has no values, it’s not included into result.
      """
      def slice(%@me{} = vela),
        do: for({serie, [h | _]} <- vela, do: {serie, h})

      @doc """
      Returns `true` if there are no values in all series, `false` otherwise.
      More performant implementation of `slice(vela) == []`.

      _See:_ `Vela.empty?/1`.
      """
      @spec empty?(Vela.t()) :: boolean()
      def empty?(%@me{} = vela),
        do: Enum.all?(vela, &match?({_, []}, &1))

      @doc """
      Empties the `Vela` given as an argument, preserving all the internal information
      (`__meta__`, `__errors__` etc.)

      _See:_ `Vela.empty!/1`.
      """
      @spec empty!(Vela.t()) :: Vela.t()
      def empty!(%@me{} = vela),
        do: Vela.map(vela, fn {serie, _} -> {serie, []} end)

      @doc """
      Merges two `Vela`s, using `resolver/3` given as the third argument in a case of ambiguity.

      _See:_ `Vela.merge/3`.
      """
      @spec merge(Vela.t(), Vela.t(), (Vela.serie(), Vela.value(), Vela.value() -> Vela.value())) ::
              Vela.t()
      def merge(%@me{} = v1, %@me{} = v2, resolver) do
        kvs =
          Enum.zip_with(v1, v2, fn {serie, v1}, {serie, v2} ->
            {serie, resolver.(serie, v1, v2)}
          end)

        struct(v1, kvs)
      end

      @impl Vela
      @doc """
      Implementation of `c:Vela.average/2`.

      Returns a slice of all series as `keyword()` in format `{Vela.serie(), Vela.value()}`,
      when the `value` is a calculated average of all serie values.

      The second parameter might be either a function of arity `1`, accepting a serie (a list of values),
      or a module, exporting `average/1` function.

      The result is similar to what `slice/1` returns, but with average values.
      """
      def average(%@me{} = vela, averager) do
        for {serie, values} <- vela do
          value =
            case averager do
              f when is_function(f, 1) -> f.(values)
              m when is_atom(m) -> m.average(values)
            end

          {serie, value}
        end
      end

      def average(_not_wellformed_vela, _averager), do: nil

      @impl Vela
      @doc """
      Implementation of `c:Vela.purge/2`.

      Purges values which are not passing `validator` given as a second parameter.
      """
      def purge(%@me{} = vela, validator \\ nil),
        do: Vela.purge(vela, validator)

      @impl Vela
      @doc """
      Implementation of `c:Vela.delta/2`.

      Delegates to `Vela.δ/2`.
      """
      def delta(%@me{} = vela, comparator \\ nil),
        do: Vela.δ(vela, comparator)

      @impl Vela
      @doc """
      Implementation of `c:Vela.equal?/2`.

      Delegates to `Vela.equal?/2`.
      """
      def equal?(%@me{} = v1, %@me{} = v2),
        do: Vela.equal?(v1, v2)
    end
  end

  @doc false
  defmacro __using__(opts) when is_list(opts) do
    typedefs = for {k, v} <- opts, do: {k, v[:type]}
    typedef = use_types(typedefs)
    opts = for {serie, desc} <- opts, do: {serie, Keyword.delete(desc, :type)}

    do_def_using(__CALLER__.module, opts, typedef)
  end

  defmacro __using__(opts) do
    quote generated: true, location: :keep do
      @__opts__ unquote(opts)
      unquote(Vela.do_def_using())
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
  def implement_enumerable(%Macro.Env{module: module}, bytecode),
    do: do_implement_enumerable(module)

  @spec map(vela :: t(), (kv() -> kv())) :: t()
  @doc """
  Maps the series using `fun` and returns the new `Vela` instance with series mapped
  """
  def map(%mod{} = vela, fun) do
    mapped =
      vela
      |> Map.take(mod.series())
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
    validator = type.config(serie, :validator, data)
    compare_by = type.config(serie, :compare_by, data)

    within_threshold =
      within_threshold?(Vela.δ(data)[serie], type.config(serie, :threshold, data), compare_by)

    validator = make_arity_2(validator)

    fn serie, value ->
      within_threshold.(value) && validator.(serie, value)
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
            do: {type.config(serie, :compare_by, vela), type.config(serie, :comparator, vela)},
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
  @doc """
  Returns `true` if velas given as arguments are of the same type _and_
  series values equal for each serie.

  This function does not check internal state, only the values.
  """
  @doc since: "0.9.2"
  def equal?(%type{} = v1, %type{} = v2) do
    [v1, v2]
    |> Enum.map(&Vela.flat_map/1)
    |> Enum.reduce(&do_equal?/2)
  end

  def equal?(_, _), do: false

  @doc "Returns `true` if the `Vela` is empty, `false` otherwise."
  @spec empty?(Vela.t()) :: boolean()
  def empty?(%type{} = vela), do: type.empty?(vela)

  @doc "Empties the values for all series of `Vela` given."
  @spec empty!(Vela.t()) :: Vela.t()
  def empty!(%type{} = vela), do: type.empty!(vela)

  @doc """
  Merges two `Vela`s given using `resolver/3` function.

  This function does not allow merging states, the first argument wins. To update state,
  use `update_state/2`.
  """
  @spec merge(Vela.t(), Vela.t(), (Vela.serie(), Vela.value(), Vela.value() -> Vela.value())) ::
          Vela.t()
  def merge(%type{} = v1, %type{} = v2, resolver), do: type.merge(v1, v2, resolver)

  @spec do_equal?(kw1 :: [Vela.kv()], kw2 :: [Vela.kv()]) :: boolean()
  defp do_equal?([], []), do: true
  defp do_equal?([], _), do: false
  defp do_equal?(_, []), do: false
  defp do_equal?(kw1, kw2) when length(kw1) != length(kw2), do: false

  defp do_equal?(kw1, kw2) do
    [kw1, kw2]
    |> Enum.zip()
    |> Enum.reduce_while(true, fn
      {{serie, %mod{} = value1}, {serie, %mod{} = value2}}, true ->
        equal? =
          cond do
            mod.__info__(:functions)[:equal?] == 2 -> mod.equal?(value1, value2)
            mod.__info__(:functions)[:compare] == 2 -> mod.compare(value1, value2) == :eq
            true -> value1 == value2
          end

        if equal?, do: {:cont, true}, else: {:halt, false}

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
    min_threshold = min * ((100 - threshold) / 100)
    max_threshold = max * ((100 + threshold) / 100)

    &(compare_by.(&1) >= min_threshold and compare_by.(&1) <= max_threshold)
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
