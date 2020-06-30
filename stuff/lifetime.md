# Vela Lifetime

`Vela` is designed to collect and keep a set of series of different values. Each serie is supposed to keep _validated_, _ordered_, _actual_ values. 

- validation is being done upon insertion, using `validator` parameter for this particular serie (_default:_ always allow;) if the validation fails, the value gets discarded immediately
- obsoleted values are removed by explicit call to `purge/2`
- sorting is done with `sorter`/`compare_by` pair of parameters; default sorting is none (_LIFO_) and the default comparator is `itself`.

Consider the following example. Let’s declare `Vela` having two series, one with integers, another with dates. We want both to be sorted descending so that we could get the most actual values at any time.

```elixir
defmodule Checkers do
  def good_integer(:integers, int) when is_integer(int), do: true
  def good_integer(_, _), do: false

  def good_date(:dates, %Date{}), do: true
  def good_date(_, _), do: false

  def compare_dates(%Date{} = d1, %Date{} = d2),
    do: Date.compare(d1, d2) == :gt
end

defmodule Series do
  import Checkers

  use Vela,
    integers: [limit: 3, validator: &good_integer/2, sorter: &>=/2],
    dates: [limit: 3, validator: &good_date/2, sorter: &compare_dates/2]
end
```

Now we can fill the struct with values.

```elixir
iex|1> s = %Series{}
#⇒ %Series{__errors__: [], dates: [], integers: []}
iex|2> put_in s, [:integers], 42
#⇒ %Series{__errors__: [], dates: [], integers: '*'}
iex|3> put_in s, [:integers], "42"
#⇒ %Series{__errors__: [integers: "42"], dates: [], integers: []}
iex|4> put_in s, [:dates], Date.utc_today
#⇒ %Series{__errors__: [], dates: [~D[2020-06-30]], integers: []}
iex|5> put_in s, [:dates], "42"   
#⇒ %Series{__errors__: [dates: "42"], dates: [], integers: []}
```

Let’s see how sorting works.

```elixir
iex|6> s
...|6> |> put_in([:integers], 10)
...|6> |> put_in([:integers], 20)
...|6> |> put_in([:integers], 30)
...|6> |> put_in([:integers], 40)
...|6> |> put_in([:integers], 0)
%Series{__errors__: [], dates: [], integers: [40, 30, 20]}
```

We instructed the serie to keep at most three values, sorted descending.

---

The get to the most “relevant” values (heads of series,) one might use `slice/1`. It returns the keyword with all the actual values.

```elixir
iex|7> Series.slice s
#⇒ [integers: 40]
```

To get to the head of each serie, one might use `Access` as shown below.

```elixir
iex|8> get_in s, [:integers]
#⇒ 40
```