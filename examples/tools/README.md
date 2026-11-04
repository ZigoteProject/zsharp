# Three small tools

Each under 100 lines, with only the prelude, Core and Std (track S's exit test): what a day-one
program looks like, and what the library has to have for it.

| Program | What it does | Lines |
|---|---|---|
| [grep.zs](grep.zs) | the lines of files or standard input containing a text: `-i`, `-n`, `-v`; grep's exit codes | 38 |
| [jsonpp.zs](jsonpp.zs) | a JSON file indented (`Json.pretty`), or `--compact` on one line; a parse error with its place | 16 |
| [tail.zs](tail.zs) | the last lines of a file (`-n`), and with `-f` the lines appended after, polled every 200 ms, stopping when the file is gone | 49 |

```sh
zs run examples/tools/grep.zs -- -i -n apple notes.txt
zs run examples/tools/jsonpp.zs -- data.json
zs run examples/tools/tail.zs -- -n 20 -f server.log
```

`tests/examples_tools.sh` builds and runs them.
