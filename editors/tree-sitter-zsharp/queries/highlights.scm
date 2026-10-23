; Z# highlighting (capture names as used by Zed and nvim-treesitter)

(comment) @comment
(import_c_declaration "c" @keyword)
((comment) @comment.doc (#match? @comment.doc "^///"))
(string) @string
(char) @string
(interpolated_string) @string
(escape_sequence) @string.escape
(interpolation ["{" "}"] @punctuation.special)
(format_specifier) @string.special
(format_width) @number
(number) @number
(measured_number) @number
(boolean) @boolean
(unit) @constant.builtin
(wildcard) @variable.special

[
  "let" "rec" "and" "mutable" "private" "type" "of" "with" "member" "static" "extern" "import" "open"
  "module" "namespace" "trait" "impl" "abstract" "derive" "fun" "match" "when" "as" "if" "then" "else"
  "for" "in" "do" "while" "not" "use" "return" "unsafe" "dyn" "function" "yield" "effect" "handle"
] @keyword

(let_bang "!" @keyword)
(do_bang "!" @keyword)
(return_expression "!" @keyword)
(yield_expression "!" @keyword)
(computation_expression builder: (identifier) @keyword)

[
  "=" "<>" "<" ">" "<=" ">=" "+" "-" "*" "/" "%" "|>" ">>" "&&" "||" "&&&" "|||" "^^^" "<<<" ">>>" "~~~" "::" "@" "->" "<-" "?"
  "+=" "-=" "*=" "/=" "%=" "&&&=" "|||=" "^^^="
  ".." "^"
] @operator

[(compare_operator) (cons_operator) (add_operator) (multiply_operator) (power_operator) (prefix_operator)] @operator

["(" ")" "[" "]" "[|" "|]" "{" "}" "[<" ">]"] @punctuation.bracket
["," ";" ":" "." "|"] @punctuation.delimiter

; declarations
(let_declaration name: (identifier) @function)
(and_definition name: (identifier) @function)
(let_declaration name: (qualified_identifier) @function)
(let_declaration name: (active_pattern_name) @function)
(let_function name: (identifier) @function)
(definition name: (identifier) @function)
(member_declaration name: (identifier) @function.method)
(member_declaration self: (identifier) @variable.special)
(abstract_member name: (identifier) @function.method)
(extern_declaration name: (identifier) @function)
(type_declaration name: (identifier) @type)
(and_type name: (identifier) @type)
(type_extension name: (identifier) @type)
(trait_declaration name: (identifier) @type)
(effect_declaration name: (identifier) @type)
(handle_rule operation: (_) @function.method)
(handle_rule resumption: (identifier) @variable.special)
(impl_declaration trait: (identifier) @type)
(derive_declaration name: (identifier) @type)
(open_declaration module: (identifier) @namespace)
(module_declaration name: (identifier) @namespace)
(attribute name: (identifier) @attribute)
(union_case name: (identifier) @constructor)
(field_declaration name: (identifier) @property)
(case_field name: (identifier) @property)
(field_value name: (identifier) @property)
(field_pattern name: (identifier) @property)
(member_access member: (identifier) @property)
(typed_parameter name: (identifier) @variable.parameter)
(member_parameter name: (identifier) @variable.parameter)

; types
(type_name) @type
(type_variable) @type
(measure (identifier) @type)

; calls and constructors (constructors start with an upper-case letter)
(application function: (identifier) @function.call)
(application function: (qualified_identifier) @function.call)
((identifier) @constructor (#match? @constructor "^[A-Z]"))
(constructor_pattern constructor: (_) @constructor)

(identifier) @variable
