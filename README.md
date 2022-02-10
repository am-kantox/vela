# ![Vela](https://raw.githubusercontent.com/am-kantox/vela/master/stuff/vela-48x48.png) Vela    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/vela/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/vela/workflows/Dialyzer/badge.svg)

**The tiny library to ease handling expiring invalidated cached series**

## Installation

```elixir
def deps do
  [
    {:vela, "~> 0.12"}
  ]
end
```

## Changelog

- **`0.13.1`** — `state/1` and `update_state/2` to keep some additional date alongside with `Vela`
- **`0.12.0`** — `threshold` does not depend on the band anymore
- **`0.11.0`** — `__meta__` might be now used to overwrite compiled in serie settings
- **`0.9.5`** — early return the value provided by existing comparison function in `equal?/2`
- **`0.9.3`** — allow `:atom` and `{GenServer, :on_start}` as type definition
- **`0.9.0`** — allow a precise type definition of each serie via `type: type()` keyword parameter
  a series keyword parameter
- **`0.8.0`** — allow a `corrector/2` callback to allow correction of rejected values as
  a series keyword parameter
- **`0.7.2`** — `Vela.put/3`
- **`0.7.0`** — exact type and behaviour for those using `Vela`
- **`0.6.3`** — fix `threshold` to use `compare_by/1` for cumbersome values
- **`0.6.1`** — use `threshold` to prevent adding outliers to series
- **`0.6.0`** — `Vela.δ/2` / `c:Vela.delta/2` returning a keyword `[{serie, {min, max}}]`

## [Documentation](https://hexdocs.pm/vela)
