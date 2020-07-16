global_settings = "~/.iex.exs"
if File.exists?(global_settings), do: Code.require_file(global_settings)

Application.put_env(:elixir, :ansi_enabled, true)

IEx.configure(
  inspect: [limit: :infinity],
  colors: [
    eval_result: [:cyan, :bright],
    eval_error: [[:red, :bright, "\n▶▶▶\n"]],
    eval_info: [:yellow, :bright],
    syntax_colors: [
      number: :red,
      atom: :blue,
      string: :green,
      boolean: :magenta,
      nil: :magenta,
      list: :white
    ]
  ],
  default_prompt:
    [
      # cursor ⇒ column 1
      "\e[G",
      :blue,
      "%prefix",
      :red,
      "|🕯️ |",
      :blue,
      "%counter",
      " ",
      :yellow,
      "▶",
      :reset
    ]
    |> IO.ANSI.format()
    |> IO.chardata_to_string()
)

alias Kantox.{Rate, Points}

defmodule G do
  def rs(rate \\ 1.2345), do: RatesBlender.Factory.rate(:string, value: rate)
  def r(rate \\ 1.2345), do: RatesBlender.Factory.rate(:object, value: rate)
  def spam_dkk(),
    do: :string |> RatesBlender.Factory.rates(value: 1.05) |> Enum.each(&Broadway.test_messages(RatesBlender.Broadway, [&1]))
end
