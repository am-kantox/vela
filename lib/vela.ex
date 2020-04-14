defmodule Vela do
  @moduledoc """
  `Vela` is a tiny library providing easy management of
  validated cached state with some history.

  Including `use Vela` in your module would turn the module
  into struct, setting field accordingly to the specification,
  passed as a parameter.

  `Vela` allows the following configurable parameters per field:

  - `limit` — length of the series to keep (default `5`)
  - `compare_by` — comparator extraction function to extract the value, to be used for
    comparison, from the underlying terms (by default it returns the whole value)
  - `validator` — the function to be used to invalidate the accumulated values
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
        def valid?(_serie, value) do
          value > 0
        end

        @spec comparator(%{created_at :: DateTime.t()}) :: DateTime.t()
        def comparator(%{created_at: created_at}),
          do: created_at

        @spec validator(serie :: atom(), value :: t()) :: boolean()
        def validator(_, value),
          do: is_integer(value) and value > 300
      end

  In the example above, before any structure update attempt
  (via `Access`,) this `valid?/3` function would be called.

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

  @typedoc "Represents the struct created by this behaviour module"
  @type t :: %{
          :__struct__ => atom(),
          :__errors__ => keyword(),
          :__meta__ => keyword(),
          optional(serie()) => [value()]
        }

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @moduledoc false

      @compile {:inline, series: 0}

      {meta, opts} = Keyword.pop(opts, :mη, [])

      @after_compile {Vela, :implement_enumerable}

      @config Enum.map(opts, fn {serie, vela} ->
                vela =
                  vela
                  |> Keyword.put_new(:compare_by, &Vela.Stubs.itself/1)
                  |> Keyword.update(:validator, &Vela.Stubs.validate/2, fn existing ->
                    case existing do
                      fun when is_function(fun, 2) ->
                        fun

                      m when is_atom(m) ->
                        &m.valid?/2

                      other ->
                        raise Vela.AccessError, field: :validator, source: &__MODULE__.purge/2
                    end
                  end)

                {serie, vela}
              end)

      @fields Keyword.keys(@config)
      @field_count Enum.count(@fields)

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

      @spec series :: [Vela.serie()]
      @doc false
      def series, do: @fields_ordered

      use Vela.Access, @config

      @spec purge(Vela.t(), nil | (Vela.serie(), Vela.value() -> boolean())) :: Vela.t()
      def purge(vela, validator \\ nil)

      def purge(%__MODULE__{} = vela, nil) do
        purged =
          for {serie, list} <- vela,
              serie in series(),
              compare_by = Keyword.get(@config[serie], :compare_by),
              validator = Keyword.get(@config[serie], :validator),
              do: {serie, Enum.filter(list, &validator.(serie, compare_by.(&1)))}

        struct(vela, purged)
      end

      def purge(%__MODULE__{} = vela, validator) do
        purged =
          for {serie, list} <- vela,
              serie in series(),
              do: {serie, Enum.filter(list, &validator.(serie, &1))}

        struct(vela, purged)
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
  def flat_map(%_{} = vela, fun \\ & &1) do
    for {serie, list} <- vela, value <- list, do: fun.({serie, value})
  end

  defmodule Stubs do
    @moduledoc false
    @spec itself(any()) :: any()
    def itself(any), do: any

    @spec validate(atom(), any()) :: boolean()
    def validate(_, _), do: true
  end
end
