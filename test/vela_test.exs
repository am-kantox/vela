defmodule VelaTest do
  use ExUnit.Case
  doctest Vela
  alias Test.Vela.{Struct, Struct2}

  setup_all do
    [data: %Struct{series1: [65, 66, 67], series2: [], series3: [43, 42]}]
  end

  test "state/1, update_state/2", %{data: data} do
    assert Struct.state(data) == []

    assert %Struct{__meta__: [state: [foo: :bar]]} =
             Struct.update_state(data, fn state -> Keyword.put(state, :foo, :bar) end)
  end

  test "get_in/2", %{data: data} do
    assert get_in(data, [:series1]) == 65
    assert get_in(data, [:series2]) == nil
    assert get_in(data, [:series0]) == nil
  end

  test "put_in/3", %{data: data} do
    assert %Struct{series1: ~c"DAB"} = put_in(data, [:series1], 68)
    assert %Struct{series1: ~c"DAB"} = Vela.put(data, :series1, 68)

    assert %Struct{__errors__: [series1: -68], series1: ~c"ABC", series2: []} =
             put_in(data, [:series1], -68)

    assert %Struct{__errors__: [series1: -68], series1: ~c"ABC", series2: []} =
             Vela.put(data, :series1, -68)

    assert %Struct{series2: ~c""} = put_in(data, [:series2], 68)
    assert %Struct{series2: ~c""} = Vela.put(data, :series2, 68)

    assert %Struct{series2: [-4, -3]} =
             data
             |> put_in([:series2], 0)
             |> put_in([:series2], -1)
             |> put_in([:series2], -2)
             |> put_in([:series2], -3)
             |> put_in([:series2], -4)

    assert_raise Vela.AccessError, fn ->
      put_in(data, [:series0], 68)
    end

    assert_raise Vela.AccessError, fn ->
      Vela.put(data, :series0, 68)
    end
  end

  test "pop_in/3", %{data: data} do
    assert {65, %Struct{series1: ~c"BC"}} = pop_in(data, [:series1])

    assert {nil, %Struct{series2: ~c""}} = pop_in(data, [:series2])

    assert :ok =
             with(
               {65, data} <- pop_in(data, [:series1]),
               {66, data} <- pop_in(data, [:series1]),
               {67, data} <- pop_in(data, [:series1]),
               {nil, ^data} <- pop_in(data, [:series1]),
               do: :ok
             )

    assert_raise Vela.AccessError, fn ->
      pop_in(data, [:series0])
    end
  end

  test "Enumerable implementation", %{data: data} do
    assert Enum.map(data, fn {serie, list} -> {serie, Enum.map(list, &(&1 + 1))} end) ==
             [series1: ~c"BCD", series2: [], series3: ~c",+"]

    assert Vela.map(data, fn {serie, list} -> {serie, Enum.map(list, &(&1 + 1))} end) ==
             %Struct{
               series1: ~c"BCD",
               series2: [],
               series3: ~c",+"
             }

    assert Vela.flat_map(data) ==
             [series1: 65, series1: 66, series1: 67, series3: 43, series3: 42]
  end

  test "purge/2", %{data: %mod{} = data} do
    assert mod.purge(data, fn _serie, value -> value != 66 end) ==
             %Struct{
               series1: ~c"AC",
               series2: [],
               series3: ~c"+*"
             }
  end

  test "equal?/2", %{data: %mod{} = data} do
    for mod <- [mod, Vela] do
      assert mod.equal?(data, %Struct{
               series1: [65, 66, 67],
               series2: [],
               series3: [43, 42]
             })

      refute mod.equal?(data, %Struct{series1: [65, 66], series2: [], series3: [43, 42]})
      refute mod.equal?(data, %Struct{series1: [], series2: [1], series3: [43, 42]})

      refute mod.equal?(data, %Struct{
               series1: [65, 66, 67],
               series2: [1],
               series3: [43, 42]
             })

      dt1 = DateTime.utc_now()
      dt2 = DateTime.add(dt1, 0)
      dt3 = DateTime.add(dt1, 1)

      assert mod.equal?(%Struct{series1: [dt1]}, %Struct{series1: [dt1]})
      assert mod.equal?(%Struct{series1: [dt1]}, %Struct{series1: [dt2]})
      refute mod.equal?(%Struct{series1: [dt1]}, %Struct{series1: [dt3]})
    end
  end

  test "merge/3", %{data: %mod{} = data} do
    for mod <- [mod, Vela] do
      merged = mod.merge(data, data, fn _k, v1, v2 -> v1 ++ v2 end)

      assert mod.equal?(merged, %Struct{
               series1: [65, 66, 67, 65, 66, 67],
               series2: [],
               series3: [43, 42, 43, 42]
             })
    end
  end

  test "empty?/1, empty!/1", %{data: %mod{} = data} do
    for mod <- [mod, Vela] do
      refute mod.empty?(data)

      empty = Vela.empty!(data)
      assert mod.empty?(empty)

      assert mod.equal?(empty, %Struct{series1: [], series2: [], series3: []})
      refute mod.equal?(data, empty)
    end
  end

  test "sort/3", %{data: %_mod{} = data} do
    assert %Struct{series3: [42, 43]} = put_in(data, [:series3], 100)
    assert %Struct{series3: [10, 42]} = put_in(data, [:series3], 10)
  end

  test "slice/1", %{data: %_mod{} = data} do
    assert [series1: 65, series3: 43] == Struct.slice(data)
  end

  test "δ/1", %{data: %_mod{} = data} do
    dt1 = Date.utc_today()
    dt2 = Date.add(dt1, 1)
    dt3 = Date.add(dt1, 0)
    dt4 = Date.add(dt1, -2)

    vela = %Struct2{integers: [1, 2, 5, 4, 3], dates: [dt1, dt2, dt3, dt4]}

    assert Vela.δ(vela) == [
             floats: {nil, nil},
             integers: {1, 5},
             dates: {dt4, dt2},
             maps: {nil, nil}
           ]

    assert Vela.δ(data) == [series1: {65, 67}, series2: {nil, nil}, series3: {42, 43}]
  end

  test "threshold integers" do
    vela = put_in(%Struct2{integers: []}, [:integers], 1000)
    assert %Struct2{integers: [1000]} = vela

    vela = put_in(vela, [:integers], 1001)
    assert %Struct2{integers: [1000, 1001]} = vela

    vela = put_in(vela, [:integers], 995)
    assert %Struct2{integers: [995, 1000, 1001]} = vela

    assert %Struct2{__errors__: [integers: 990], integers: [995, 1000, 1001]} =
             put_in(vela, [:integers], 990)

    assert %Struct2{__errors__: [integers: 1100], integers: [995, 1000, 1001]} =
             put_in(vela, [:integers], 1100)

    assert %Struct2{__errors__: [integers: 1100], integers: [995, 1000, 1001]} =
             put_in(%Struct2{vela | __meta__: [threshold: 9.0]}, [:integers], 1100)

    assert %Struct2{__errors__: [], integers: [995, 1000, 1001]} =
             put_in(%Struct2{vela | __meta__: [threshold: 10.0]}, [:integers], 1100)
  end

  test "threshold floats" do
    vela = put_in(%Struct2{floats: []}, [:floats], 1.0)
    assert %Struct2{floats: [1.0]} = vela

    assert %Struct2{floats: [100.0, 1.0]} = put_in(vela, [:floats], 100.0)

    assert %Struct2{__errors__: [floats: 100.0], floats: [1.0]} =
             put_in(%Struct2{vela | __meta__: [threshold: 1.0]}, [:floats], 100.0)

    assert %Struct2{__errors__: [floats: 100.0], floats: [1.0]} =
             put_in(%Struct2{vela | __meta__: [state: [threshold: 1.0]]}, [:floats], 100.0)
  end

  test "threshold with extractor" do
    vela = %Struct2{
      maps: [
        %{date: Date.from_erl!({2020, 7, 2}), number: 1000},
        %{date: Date.from_erl!({2020, 7, 1}), number: 1003}
      ]
    }

    maps = [
      %{date: Date.from_erl!({2020, 6, 30}), number: 1004},
      %{date: Date.from_erl!({2020, 7, 1}), number: 1003},
      %{date: Date.from_erl!({2020, 7, 2}), number: 1000}
    ]

    assert %Struct2{maps: ^maps} =
             put_in(vela, [:maps], %{date: Date.from_erl!({2020, 6, 30}), number: 1004})

    maps = [
      %{date: Date.from_erl!({2020, 7, 1}), number: 1003},
      %{date: Date.from_erl!({2020, 7, 2}), number: 1000},
      %{date: Date.from_erl!({2020, 7, 3}), number: 995}
    ]

    assert %Struct2{maps: ^maps} =
             put_in(vela, [:maps], %{date: Date.from_erl!({2020, 7, 3}), number: 995})

    errors = [maps: %{date: Date.from_erl!({2020, 7, 3}), number: 990}]

    assert %Struct2{
             __errors__: ^errors
           } = put_in(vela, [:maps], %{date: Date.from_erl!({2020, 7, 3}), number: 990})
  end

  test "corrector/3" do
    vela = %Struct2{integers: [1, 3]}

    assert %Struct2{__errors__: [integers: 5], integers: [1, 3]} = put_in(vela, [:integers], 5)
    assert %Struct2{__errors__: [], integers: [1, 3, 42]} = put_in(vela, [:integers], 42)
  end
end
