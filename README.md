# ![Vela](https://raw.githubusercontent.com/am-kantox/vela/master/stuff/vela-48x48.png) Vela

**The tiny library to ease handling expiring invalidated cached series**

## Installation

```elixir
def deps do
  [
    {:vela, "~> 0.6"}
  ]
end
```

## Changelog

- **`0.6.2`** — fix `threshold` to use `compare_by/1` for cumbersome values
- **`0.6.1`** — use `threshold` to prevent adding outliers to series
- **`0.6.0`** — `Vela.δ/1` / `Vela.delta/1` returning a keyword `[{serie, {min, max}}]`

## [Documentation](https://hexdocs.pm/vela)
