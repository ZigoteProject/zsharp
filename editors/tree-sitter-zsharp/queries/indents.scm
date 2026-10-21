; indent after a line that opens a block: `=`, `->`, `then`, `else`, `do`, `with`
[(block) (match_expression) (record) (list) (array)] @indent
["=" "->" "then" "else" "do" "with"] @indent
["}" "]" "|]" ")"] @outdent
