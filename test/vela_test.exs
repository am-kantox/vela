defmodule VelaTest do
  use ExUnit.Case
  doctest Vela

  setup_all do
    [data: %Test.Vela.Struct{series1: [65, 66, 67], series2: []}]
  end

  test "get_in/2", %{data: data} do
    assert get_in(data, [:series1]) == 65
    assert get_in(data, [:series2]) == nil
    assert get_in(data, [:series3]) == nil
  end

  test "put_in/3", %{data: data} do
    assert %Test.Vela.Struct{series1: 'DAB'} = put_in(data, [:series1], 68)

    assert %Test.Vela.Struct{__errors__: %{series1: [-68]}, series1: 'ABC', series2: []} =
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
      put_in(data, [:series3], 68)
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
      pop_in(data, [:series3])
    end
  end
end
