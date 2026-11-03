# Type providers

The types of a data source, declared from the source itself when the program is compiled
([proposal 0001](../../docs/proposals/0001-type-providers.md), [the guide's chapter](../../docs/guide/18-type-providers.md)):

```fsharp
module Weather = import json "weather.json"
module Stocks = import csv ("stocks.csv", separator = ";")
module Db = import sql "schema.sql"
```

`Weather.Root` has the sample's fields with their types, `Weather.parse` reads a document of
that shape, `Stocks.Row` is a row of the CSV file with its columns typed from every row, and
`Db.Users` is the `users` table. A key removed from `weather.json` makes the code that uses it
a compile error. Run it:

```bash
zs run examples/providers/main.zs
```

Each provided module is ordinary Z#, written to `.zs-cache/providers/` beside the program;
`zs provide json weather.json` prints it, to keep in place of the import. The chip's version is
[examples/mcu/nucleo-f401-svd.zs](../mcu/nucleo-f401-svd.zs): the STM32F401's registers from
its SVD file, each a `[<Bits>]` record.
