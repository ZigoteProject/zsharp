(namespace_declaration "namespace" @context name: (_) @name) @item
(module_declaration "module" @context name: (_) @name) @item
; the outline / symbol list
(let_declaration "let" @context name: (_) @name) @item
(and_definition "and" @context name: (_) @name) @item
(type_declaration "type" @context name: (identifier) @name) @item
(type_extension "type" @context name: (identifier) @name) @item
(trait_declaration "trait" @context name: (identifier) @name) @item
(impl_declaration "impl" @context trait: (identifier) @name) @item
(derive_declaration "derive" @context name: (identifier) @name) @item
(extern_declaration "extern" @context name: (identifier) @name) @item
(member_declaration "member" @context name: (identifier) @name) @item
(union_case name: (identifier) @name) @item
