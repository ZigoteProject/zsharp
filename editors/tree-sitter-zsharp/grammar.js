/**
 * Tree-sitter grammar for Z# (https://github.com/…/zsharp), used for highlighting, indentation
 * and the outline in Zed and other editors. The compiler's parser (src/Syntax.fs) is the
 * reference; ./test.sh parses every tests/*.zs with this grammar to keep the two in step.
 *
 * Layout: an external scanner (src/scanner.c) turns indentation into _indent/_dedent and line
 * ends into _newline, outside brackets, like tree-sitter-python.
 */

const PREC = {
  assign: 1,
  or: 4,
  and: 5,
  compare: 6, // also |>, >> and custom operators starting with < > = | & $ ? or !=, as in F#
  bitor: 7, // ||| ^^^ &&& <<< >>>: tighter than comparison, looser than :: and +
  bitxor: 8,
  bitand: 9,
  shift: 10,
  cons: 11,
  add: 12,
  multiply: 13,
  power: 14,
  unary: 15,
  question: 16,
  application: 17,
  member: 18,
};

const sep1 = (rule, separator) => seq(rule, repeat(seq(separator, rule)));

// custom operators: runs of these characters that aren't a built-in symbol (a string token
// wins over a regex of the same length); the first character after any dots sets precedence
const OP = '[!%&*+\\-./<=>?@^|~$]*';
const customOp = (first) => token(new RegExp('\\.*' + first + OP));
const sep = (rule, separator) => optional(sep1(rule, separator));

module.exports = grammar({
  name: 'zsharp',

  // _error_sentinel is never used by a rule: tree-sitter marks it valid only during error
  // recovery, which is how the scanner knows to stay out of the way
  externals: $ => [$._newline, $._indent, $._dedent, $._error_sentinel],

  extras: $ => [/\s/, $.comment],

  word: $ => $.identifier,

  conflicts: $ => [
    [$.match_expression],
    [$.handle_expression],
    [$.function_expression],
    [$.if_expression],
    [$._parameter, $._pattern_atom],
    [$.type_name, $.measure],
    [$._type_atom, $.measure],
    [$.as_pattern, $.tuple_pattern],
    [$._primary, $.field_value],
    [$.union_type],
    [$.union_case, $.type_name], // type T = A: an alias or a union of one case
    [$.let_declaration], // a newline after a body: the next declaration, or `and`
    [$.type_declaration], // the same after a type's body
    [$.let_function],
    [$._primary, $.computation_expression], // name { : a record argument, or a computation expression
  ],

  rules: {
    // declarations separated by newlines (a bare newline can't repeat: layout tokens are
    // zero-width, so `repeat(_newline)` would loop at one position)
    source_file: $ => seq(optional($._newline), optional(seq(sep1($._declaration, $._newline), optional($._newline)))),

    // ------------------------------------------------------------ declarations

    _declaration: $ => seq(optional(seq($.attributes, optional($._newline))), choice(
      $.let_declaration,
      $.type_declaration,
      $.type_extension,
      $.extern_declaration,
      $.import_c_declaration,
      $.trait_declaration,
      $.effect_declaration,
      $.impl_declaration,
      $.derive_declaration,
      $.open_declaration,
      $.module_declaration,
      $.namespace_declaration,
    )),

    attributes: $ => seq('[<', sep1($.attribute, ';'), '>]'),
    attribute: $ => seq(
      field('name', $.identifier),
      optional(choice($.string, seq('(', sep(choice($.identifier, $.string), ','), ')'))),
    ),

    open_declaration: $ => seq('open', field('module', choice($.identifier, $.qualified_identifier))),
    // namespace Collections: the file's types and modules are Collections.Name
    namespace_declaration: $ => seq('namespace', field('name', choice($.identifier, $.qualified_identifier))),
    module_declaration: $ => seq('module', field('name', choice($.identifier, $.qualified_identifier)),
      optional(seq('=', $._indent, sep1($._declaration, $._newline), optional($._newline), $._dedent))), // module Inner = …

    let_declaration: $ => choice(
      seq(
        'let',
        optional('rec'),
        optional('private'),
        field('name', choice($.identifier, $.qualified_identifier, $.active_pattern_name, $.operator_name)),
        repeat($._parameter),
        optional($.type_annotation),
        '=',
        field('body', $._body),
        repeat(seq($._newline, $.and_definition)), // let rec f … and g …
      ),
      // let (a, b) = …: a value for each of the pattern's variables
      seq('let', optional('private'), field('pattern', $._top_pattern), optional($.type_annotation), '=', field('body', $._body)),
    ),
    _top_pattern: $ => choice($.parenthesized_pattern, $.unit, $.record_pattern, $.wildcard, alias($.top_as_pattern, $.as_pattern)),
    top_as_pattern: $ => seq(choice($.parenthesized_pattern, $.record_pattern), 'as', $.identifier),

    and_definition: $ => seq('and', optional('private'), field('name', $.identifier), repeat1($._parameter), optional($.type_annotation), '=', field('body', $._body)),

    active_pattern_name: $ => seq('(', '|', sep1(choice($.identifier, '_'), '|'), '|', ')'),

    _parameter: $ => choice($.identifier, $.unit, $.wildcard, $.typed_parameter, $.parenthesized_pattern, $.list_pattern, $.record_pattern),
    typed_parameter: $ => seq('(', optional('?'), field('name', $.identifier), $.type_annotation, optional(seq('=', $._expression)), ')'),
    type_annotation: $ => seq(':', $._type),

    import_c_declaration: $ => seq('import', 'c', field('header', $.string)),
    extern_declaration: $ => seq('extern', field('name', $.identifier), ':', $._type),

    type_declaration: $ => seq(
      'type',
      $._type_definition,
      repeat(seq($._newline, $.and_type)), // type A = … and B = …: types that name each other
    ),
    and_type: $ => seq('and', $._type_definition),
    _type_definition: $ => seq(
      optional('private'),
      field('name', $.identifier),
      optional($.type_parameters),
      optional(seq('=', choice(
        // type T = { … }  (members below, or after `with`)
        seq($._type_body, optional($._trailing_members)),
        // type Duration = i64<ns>: an alias (a bare name is one too, as in F#; read as a union of
        // one case here, which highlights the same)
        field('alias', $.type_alias),
        // type T =  then the body indented, members after it at the same indentation
        seq(
          $._indent, $._type_body,
          repeat(seq($._newline, $.member_declaration)),
          optional(seq($._newline, 'with', $._member_block)),
          $._dedent,
        ),
        // a type with only members
        seq($._indent, sep1($.member_declaration, $._newline), $._dedent),
      ))),
    ),
    type_parameters: $ => seq('<', sep1($.type_variable, ','), '>'),
    type_alias: $ => prec.dynamic(-1, $._type),
    _type_body: $ => choice($.record_type, $.union_type),

    record_type: $ => seq('{', sep1($.field_declaration, choice(';', $._newline)), optional(choice(';', $._newline)), '}'),
    field_declaration: $ => seq(field('name', $.identifier), ':', $._type, optional(seq('=', $._expression))),

    union_type: $ => seq(optional('|'), sep1($.union_case, choice('|', seq($._newline, '|')))),
    union_case: $ => seq(field('name', $.identifier), optional(seq('of', sep1($.case_field, '*')))),
    case_field: $ => seq(optional(seq(field('name', $.identifier), ':')), $._type_atom),

    type_extension: $ => seq('type', field('name', $.identifier), optional($.type_parameters), 'with', $._member_block),

    // members after a one-line type body: `with` on the same line, or indented below it
    _trailing_members: $ => choice(
      seq('with', $._member_block),
      seq($._indent, sep1($.member_declaration, $._newline), $._dedent),
      seq($._indent, 'with', $._member_block, $._dedent),
    ),
    _member_block: $ => choice(
      $.member_declaration,
      seq($._indent, sep1($.member_declaration, $._newline), $._dedent),
    ),
    member_declaration: $ => seq(
      optional('static'),
      'member',
      optional(seq(field('self', $.identifier), '.')),
      field('name', $.identifier),
      optional(seq('(', sep($.member_parameter, ','), ')')),
      optional($.type_annotation),
      '=',
      field('body', $._body),
    ),
    member_parameter: $ => seq(optional('?'), field('name', $.identifier), optional($.type_annotation), optional(seq('=', $._expression))),

    trait_declaration: $ => seq(
      // trait Iter<'c, 'a>: the first parameter dispatches, the impl gives the others
      'trait', field('name', $.identifier), '<', sep1($.type_variable, ','), '>', '=',
      $._indent, sep1($.abstract_member, $._newline), $._dedent,
    ),
    abstract_member: $ => seq('abstract', field('name', $.identifier), ':', $._type),

    // effect Yield<'a> = abstract yield : 'a -> unit …: operations a handler gives meaning to
    effect_declaration: $ => seq(
      'effect', field('name', $.identifier), optional($.type_parameters), '=',
      choice($.abstract_member, seq($._indent, sep1($.abstract_member, $._newline), $._dedent)),
    ),

    impl_declaration: $ => seq('impl', field('trait', choice($.identifier, $.qualified_identifier)), '<', sep1($._type, ','), '>', '=', $._definitions),
    // derive Show = let show … ; or a group, derive Json = ToJson, FromJson
    derive_declaration: $ => seq('derive', field('name', $.identifier), '=', choice($._definitions, sep1(field('member', $.identifier), ','))),
    _definitions: $ => seq($._indent, sep1($.definition, $._newline), $._dedent),
    definition: $ => seq('let', field('name', $.identifier), repeat($._parameter), optional($.type_annotation), '=', field('body', $._body)),

    // ------------------------------------------------------------ types

    _type: $ => choice($.function_type, $.tuple_type, $.effect_type, $._type_atom),
    function_type: $ => prec.right(seq(choice($.tuple_type, $._type_atom), '->', $._type)),
    // a function's result and its effects: int / Throw<string>, unit / <Log, Yield<'a> | 'e>
    effect_type: $ => prec.right(seq(choice($.tuple_type, $._type_atom), '/', $.effect_row)),
    effect_row: $ => choice(
      $.type_name,
      $.generic_type,
      $.type_variable,
      '<>',
      seq('<', sep1(choice($.type_name, $.generic_type), ','), optional(seq('|', $.type_variable)), '>'),
    ),
    tuple_type: $ => prec.left(seq($._type_atom, repeat1(seq('*', $._type_atom)))),
    _type_atom: $ => choice($.type_name, $.generic_type, $.postfix_type, $.type_variable, $.variadic, $.dyn_type, seq('(', $._type, ')')),
    dyn_type: $ => seq('dyn', $.type_name), // dyn Trait
    variadic: $ => '...',
    type_name: $ => choice($.identifier, $.qualified_identifier),
    generic_type: $ => seq($.type_name, '<', sep1(choice($._type, $.measure), ','), '>'),
    postfix_type: $ => prec.left(seq($._type_atom, $.type_name)),
    type_variable: $ => /'[A-Za-z_][A-Za-z0-9_]*/,
    measure: $ => prec.left(repeat1(choice($.identifier, $.type_variable, '*', '/', '^', /-?[0-9]+/, '(', ')'))),

    // ------------------------------------------------------------ statements and blocks

    _body: $ => choice($._expression, $.assignment, $.block),
    block: $ => seq($._indent, sep1($._statement, $._newline), optional($._newline), $._dedent),

    _statement: $ => choice($.let_binding, $.let_function, $.let_mutable, $.use_binding, $.let_bang, $.do_bang, $.return_expression, $.assignment, $._expression),
    use_binding: $ => seq('use', field('name', $.identifier), '=', field('value', $._body)),
    // in a computation expression: let!, do!, return and return!
    let_bang: $ => seq('let', token.immediate('!'), field('pattern', $._pattern), '=', field('value', $._body)),
    do_bang: $ => seq('do', token.immediate('!'), field('value', $._body)),
    return_expression: $ => prec.right(seq('return', optional(token.immediate('!')), $._body)),
    let_binding: $ => seq('let', field('pattern', $._pattern), optional($.type_annotation), '=', field('value', $._body)),
    let_function: $ => seq('let', optional('rec'), field('name', choice($.identifier, $.operator_name)), repeat1($._parameter), optional($.type_annotation), '=', field('body', $._body),
      repeat(seq($._newline, $.and_definition))),
    let_mutable: $ => seq('let', 'mutable', field('name', $.identifier), optional($.type_annotation), '=', field('value', $._body)),
    // x <- e, and x += e (each operator's compound: a place written once)
    assignment: $ => prec.right(PREC.assign, seq($._expression, field('operator', choice('<-', '+=', '-=', '*=', '/=', '%=', '&&&=', '|||=', '^^^=')), $._expression)),

    // ------------------------------------------------------------ expressions

    _expression: $ => choice(
      $.if_expression,
      $.match_expression,
      $.handle_expression,
      $.function_expression,
      $.lambda,
      $.yield_expression,
      $.unsafe_expression,
      $.for_expression,
      $.while_expression,
      $.binary_expression,
      $.unary_expression,
      $.application,
      $.question,
      $._primary,
    ),

    // `else` may start the next line, so a newline after the then-branch is ambiguous until
    // the next token: the declared conflict lets the parser try both
    if_expression: $ => seq(
      'if', field('condition', $._expression), 'then', field('then', $._body),
      optional(seq(optional($._newline), 'else', field('else', $._body))),
    ),

    // like `if`: after an arm, a newline may lead to another `|` or to the next statement
    match_expression: $ => (seq(
      'match', field('value', $._expression), 'with',
      choice(
        $.single_rule, // match p with (a, b) -> (b, a)
        repeat1(seq(optional($._newline), $.match_rule)),
        seq($._indent, repeat1(seq(optional($._newline), $.match_rule)), $._dedent),
      ),
    )),
    single_rule: $ => prec.right(seq(field('pattern', $._pattern), '->', field('body', $._body))),

    // handle e with | E.op x, k -> … | return x -> …: e's operations of E given meaning
    handle_expression: $ => seq(
      'handle', field('value', choice($._expression, $.block)), optional($._newline), 'with',
      choice(
        repeat1(seq(optional($._newline), $.handle_rule)),
        seq($._indent, repeat1(seq(optional($._newline), $.handle_rule)), $._dedent),
      ),
    ),
    handle_rule: $ => prec.right(seq(
      '|',
      choice(
        seq('return', field('pattern', $._pattern)),
        seq(field('operation', choice($.identifier, $.qualified_identifier)), repeat($._pattern_atom), ',', field('resumption', choice($.identifier, $.wildcard))),
      ),
      '->',
      field('body', $._body),
    )),
    match_rule: $ => prec.right(seq(
      '|', field('pattern', $._pattern), optional(seq('when', field('guard', $._expression))), '->', field('body', $._body),
    )),

    // function | p -> e …: a lambda matching its argument
    function_expression: $ => seq(
      'function',
      choice(
        seq($.single_rule, repeat($.match_rule)), // function Some x -> x | None -> 0
        repeat1(seq(optional($._newline), $.match_rule)),
        seq($._indent, repeat1(seq(optional($._newline), $.match_rule)), $._dedent),
      ),
    ),

    lambda: $ => prec.right(seq('fun', repeat1($._parameter), '->', $._body)),

    // in a list or array expression: yield e, or yield! xs for each of xs
    yield_expression: $ => prec.right(seq('yield', optional(token.immediate('!')), $._expression)),

    // unsafe e, or unsafe and an indented block
    unsafe_expression: $ => prec.right(seq('unsafe', $._body)),

    for_expression: $ => seq(
      'for', field('variable', $._pattern), 'in', // a name, or a pattern over a collection's elements
      choice(
        seq($._expression, '..', $._expression, optional(seq('..', $._expression))),
        $._expression,
      ),
      choice('do', '->'), field('body', $._body), // -> e yields e, in a list expression
    ),
    while_expression: $ => seq('while', field('condition', $._expression), 'do', field('body', $._body)),

    binary_expression: $ => choice(
      prec.right(PREC.or, seq($._expression, field('operator', '||'), $._expression)),
      prec.right(PREC.and, seq($._expression, field('operator', '&&'), $._expression)),
      prec.left(PREC.compare, seq($._expression, field('operator', choice('|>', '>>', '=', '<>', '<', '>', '<=', '>=', $.compare_operator)), $._expression)),
      prec.left(PREC.bitor, seq($._expression, field('operator', '|||'), $._expression)),
      prec.left(PREC.bitxor, seq($._expression, field('operator', '^^^'), $._expression)),
      prec.left(PREC.bitand, seq($._expression, field('operator', '&&&'), $._expression)),
      prec.left(PREC.shift, seq($._expression, field('operator', choice('<<<', '>>>')), $._expression)),
      prec.right(PREC.cons, seq($._expression, field('operator', choice('::', '@', $.cons_operator)), $._expression)),
      prec.left(PREC.add, seq($._expression, field('operator', choice('+', '-', $.add_operator)), $._expression)),
      prec.left(PREC.multiply, seq($._expression, field('operator', choice('*', '/', '%', $.multiply_operator)), $._expression)),
      prec.right(PREC.power, seq($._expression, field('operator', $.power_operator), $._expression)),
    ),
    unary_expression: $ => prec(PREC.unary, seq(choice('-', 'not', '~~~'), $._expression)),
    question: $ => prec(PREC.question, seq($._expression, '?')),

    application: $ => prec.left(PREC.application, seq(field('function', $._primary), repeat1(field('argument', $._primary)))),

    _primary: $ => choice(
      $.computation_expression,
      $.identifier,
      $.qualified_identifier,
      $.member_access,
      $.index_access,
      $.number,
      $.measured_number,
      $.char,
      $.string,
      $.interpolated_string,
      $.boolean,
      $.unit,
      $.parenthesized_expression,
      $.operator_value,
      $.prefix_expression,
      $.typed_expression,
      $.tuple,
      $.list,
      $.array,
      $.record,
      $.record_update,
    ),

    // task { … }: a builder's name, then statements, on the line or as an indented block
    computation_expression: $ => seq(
      field('builder', $.identifier), '{',
      choice(seq($._indent, sep1($._statement, $._newline), optional($._newline), $._dedent), $._statement),
      '}',
    ),

    member_access: $ => prec.left(PREC.member, seq($._primary, '.', field('member', $.identifier))),
    index_access: $ => prec.left(PREC.member, seq($._primary, '.', '[', choice($._expression, $.slice_range), ']')),
    // a.[i..j], a.[i..], a.[..j]
    slice_range: $ => choice(seq($._expression, '..', optional($._expression)), seq('..', $._expression)),
    parenthesized_expression: $ => seq('(', $._expression, ')'),
    // (>>=), or a built-in operator as a function: (+)
    operator_value: $ => seq('(', choice($._custom_operator, '+', '-', '*', '/', '%', '=', '<>', '<', '>', '<=', '>=', '&&&', '|||', '^^^', '<<<', '>>>', '@', '::'), ')'),
    operator_name: $ => seq('(', $._custom_operator, ')'),
    _custom_operator: $ => choice($.compare_operator, $.cons_operator, $.add_operator, $.multiply_operator, $.power_operator, $.prefix_operator),
    compare_operator: $ => customOp('([<>=|&$?]|!=)'),
    // !r, ~~x: starting with ! (but not !=) or ~, and binding tighter than application
    prefix_operator: $ => token(new RegExp('(![!%&*+\\-./<>?@^|~$]|~)' + OP + '|!')),
    prefix_expression: $ => prec(PREC.application, seq(field('operator', $.prefix_operator), $._primary)),
    cons_operator: $ => customOp('[@^]'),
    add_operator: $ => customOp('[+\\-]'),
    multiply_operator: $ => customOp('[*/%]'),
    power_operator: $ => token(prec(1, new RegExp('\\.*\\*\\*' + OP))),
    typed_expression: $ => seq('(', $._expression, ':', field('type', $._type), ')'),
    tuple: $ => seq('(', $._expression, repeat1(seq(',', $._expression)), ')'),
    // [ a; b ], or the items on lines of their own, deeper than the line the bracket is on
    list: $ => seq('[', optional(choice($._items, seq($._indent, $._items, optional($._dedent)))), ']'),
    array: $ => seq('[|', optional(choice($._items, seq($._indent, $._items, optional($._dedent)))), '|]'),
    _items: $ => seq(sep1($._expression, choice(';', $._newline)), optional(choice(';', $._newline))),
    record: $ => seq('{', sep1($.field_value, choice(';', $._newline)), optional(choice(';', $._newline)), '}'),
    record_update: $ => seq('{', $._expression, 'with', sep1($.field_value, choice(';', $._newline)), optional(choice(';', $._newline)), '}'),
    field_value: $ => seq(field('name', $.identifier), '=', $._expression),

    // ------------------------------------------------------------ patterns

    _pattern: $ => choice($.or_pattern, $.as_pattern, $.tuple_pattern, $.cons_pattern, $.constructor_pattern, $._pattern_atom),
    or_pattern: $ => prec.left(1, seq($._pattern, '|', $._pattern)),
    as_pattern: $ => prec.left(0, seq($._pattern, 'as', $.identifier)),
    tuple_pattern: $ => prec.left(2, seq($._pattern, repeat1(seq(',', $._pattern)))),
    cons_pattern: $ => prec.right(3, seq($._pattern, '::', $._pattern)),
    constructor_pattern: $ => prec(4, seq(field('constructor', choice($.identifier, $.qualified_identifier)), repeat1($._pattern_atom))),
    _pattern_atom: $ => choice(
      $.identifier,
      $.qualified_identifier,
      $.wildcard,
      $.number,
      $.negative_pattern,
      $.char,
      $.string,
      $.boolean,
      $.unit,
      $.parenthesized_pattern,
      $.list_pattern,
      $.named_fields_pattern,
      $.record_pattern,
    ),
    parenthesized_pattern: $ => seq('(', $._pattern, ')'),
    negative_pattern: $ => seq('-', $.number), // | -1 -> …
    list_pattern: $ => seq('[', sep($._pattern, ';'), ']'),
    named_fields_pattern: $ => seq('(', sep1(seq($.identifier, '=', $._pattern), choice(',', ';')), ')'),
    record_pattern: $ => seq('{', sep1($.field_pattern, choice(';', $._newline)), optional(choice(';', $._newline)), '}'),
    field_pattern: $ => seq(field('name', $.identifier), '=', $._pattern),
    wildcard: $ => '_',

    // ------------------------------------------------------------ tokens

    // ``name``: a name that may be a keyword (Parallel.for is defined as ``for``)
    identifier: $ => /[A-Za-z_][A-Za-z0-9_]*|``[^`\n]+``/,
    qualified_identifier: $ => token(seq(/[A-Z][A-Za-z0-9_]*/, repeat1(seq('.', /[A-Za-z_][A-Za-z0-9_]*/)))),
    number: $ => token(choice(/0[xX][0-9a-fA-F_]+/, /0[bB][01_]+/, /0[oO][0-7_]+/, /[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?/, /[0-9][0-9_]*/)),
    measured_number: $ => seq($.number, token.immediate('<'), $.measure, '>'),
    boolean: $ => choice('true', 'false'),
    unit: $ => seq('(', ')'),
    string: $ => choice(
      seq('"', repeat(choice($.string_content, $.escape_sequence)), '"'),
      // """…""": raw text, which may hold quotes and line breaks
      token(seq('"""', repeat(choice(/[^"]/, /"[^"]/, /""[^"]/)), '"""')),
    ),
    interpolated_string: $ => seq('$"', repeat(choice($.interpolated_content, $.escape_sequence, $.interpolation)), '"'),
    // {x}, {x,10} (padded to 10 characters, -10 on the right), {x:F2} (a .NET format), {x,8:F1}
    interpolation: $ => seq(
      '{', $._expression,
      optional(seq(',', field('width', $.format_width))),
      optional(seq(':', field('format', $.format_specifier))),
      '}',
    ),
    format_width: $ => /-?[0-9]+/,
    format_specifier: $ => token.immediate(/[A-Za-z][0-9]{0,2}/),
    string_content: $ => token.immediate(prec(1, /[^"\\]+/)),
    interpolated_content: $ => token.immediate(prec(1, /[^"\\{}]+/)),
    escape_sequence: $ => token.immediate(choice(/\\[nrt0\\"']/, /\\u\{[0-9a-fA-F]+\}/, '{{', '}}')),
    // 'a', '\n', '\u{e9}' (longer than a type variable 'a, so the lexer prefers it when it fits)
    char: $ => token(seq("'", choice(/[^'\\\n]/, /\\[nrt0\\"']/, /\\u\{[0-9a-fA-F]+\}/), "'")),
    comment: $ => token(seq('//', /.*/)),
  },
});
