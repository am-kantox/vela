defmodule VelaTest do
  use ExUnit.Case
  doctest Vela

  setup_all do
    [data: %Test.Vela.Struct{series1: [65, 66, 67], series2: [], series3: [43, 42]}]
  end

  test "get_in/2", %{data: data} do
    assert get_in(data, [:series1]) == 65
    assert get_in(data, [:series2]) == nil
    assert get_in(data, [:series0]) == nil
  end

  test "put_in/3", %{data: data} do
    assert %Test.Vela.Struct{series1: 'DAB'} = put_in(data, [:series1], 68)

    assert %Test.Vela.Struct{__errors__: [series1: -68], series1: 'ABC', series2: []} =
             put_in(data, [:series1], -68)

    assert %Test.Vela.Struct{series2: ''} = put_in(data, [:series2], 68)

    assert %Test.Vela.Struct{series2: [-4, -3]} =
             data
             |> put_in([:series2], 0)
             |> put_in([:series2], -1)
             |> put_in([:series2], -2)
             |> put_in([:series2], -3)
             |> put_in([:series2], -4)

    assert_raise Vela.AccessError, fn ->
      put_in(data, [:series0], 68)
    end
  end

  test "pop_in/3", %{data: data} do
    assert {65, %Test.Vela.Struct{series1: 'BC'}} = pop_in(data, [:series1])

    assert {nil, %Test.Vela.Struct{series2: ''}} = pop_in(data, [:series2])

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
             [series1: 'BCD', series2: [], series3: ',+']

    assert Vela.map(data, fn {serie, list} -> {serie, Enum.map(list, &(&1 + 1))} end) ==
             %Test.Vela.Struct{
               series1: 'BCD',
               series2: [],
               series3: ',+'
             }

    assert Vela.flat_map(data) ==
             [series1: 65, series1: 66, series1: 67, series3: 43, series3: 42]
  end

  test "purge/2", %{data: %mod{} = data} do
    assert mod.purge(data, fn _serie, value -> value != 66 end) ==
             %Test.Vela.Struct{
               series1: 'AC',
               series2: [],
               series3: '+*'
             }
  end

  test "equal?/2", %{data: %mod{} = data} do
    assert mod.equal?(data, %Test.Vela.Struct{
             series1: [65, 66, 67],
             series2: [],
             series3: [43, 42]
           })

    refute mod.equal?(data, %Test.Vela.Struct{series1: [65, 66], series2: [], series3: [43, 42]})
    refute mod.equal?(data, %Test.Vela.Struct{series1: [], series2: [1], series3: [43, 42]})

    refute mod.equal?(data, %Test.Vela.Struct{
             series1: [65, 66, 67],
             series2: [1],
             series3: [43, 42]
           })

    dt1 = DateTime.utc_now()
    dt2 = DateTime.add(dt1, 0)
    dt3 = DateTime.add(dt1, 1)

    assert mod.equal?(%Test.Vela.Struct{series1: [dt1]}, %Test.Vela.Struct{series1: [dt1]})
    assert mod.equal?(%Test.Vela.Struct{series1: [dt1]}, %Test.Vela.Struct{series1: [dt2]})
    refute mod.equal?(%Test.Vela.Struct{series1: [dt1]}, %Test.Vela.Struct{series1: [dt3]})
  end

  test "sort/2", %{data: %_mod{} = data} do
    assert %Test.Vela.Struct{series3: [42, 43]} = put_in(data, [:series3], 100)
    assert %Test.Vela.Struct{series3: [10, 42]} = put_in(data, [:series3], 10)
  end
end
