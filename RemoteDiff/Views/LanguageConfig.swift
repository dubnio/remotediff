import Foundation

// MARK: - Language Configuration
// Keyword lists sourced from highlight.js (github.com/highlightjs/highlight.js)
// and Pygments (pygments.org) lexer definitions.

struct LanguageConfig {
    let name: String
    let keywords: Set<String>
    let typeKeywords: Set<String>      // types/builtins highlighted differently
    let literals: Set<String>          // true, false, nil, null, etc.
    let commentLine: [String]          // e.g. ["//", "#"]
    let commentBlockStart: String?     // e.g. "/*"
    let commentBlockEnd: String?       // e.g. "*/"
    let stringDelimiters: [Character]  // e.g. ["\"", "'"]
    let templateStrings: Bool          // backtick strings (JS/TS)
    let tripleStringDelimiters: [String] // e.g. ["\"\"\"", "'''"] for Python

    init(name: String,
         keywords: Set<String> = [],
         typeKeywords: Set<String> = [],
         literals: Set<String> = ["true", "false", "null"],
         commentLine: [String] = ["//"],
         commentBlockStart: String? = "/*",
         commentBlockEnd: String? = "*/",
         stringDelimiters: [Character] = ["\"", "'"],
         templateStrings: Bool = false,
         tripleStringDelimiters: [String] = []) {
        self.name = name
        self.keywords = keywords
        self.typeKeywords = typeKeywords
        self.literals = literals
        self.commentLine = commentLine
        self.commentBlockStart = commentBlockStart
        self.commentBlockEnd = commentBlockEnd
        self.stringDelimiters = stringDelimiters
        self.templateStrings = templateStrings
        self.tripleStringDelimiters = tripleStringDelimiters
    }
}

// MARK: - Language Detection

extension LanguageConfig {
    /// Detects language from file path/extension
    static func detect(from path: String) -> LanguageConfig {
        let ext = (path as NSString).pathExtension.lowercased()
        let filename = (path as NSString).lastPathComponent.lowercased()

        // Match by filename first
        switch filename {
        case "makefile", "gnumakefile": return .makefile
        case "dockerfile": return .dockerfile
        case "cmakelists.txt": return .cmake
        case ".gitignore", ".dockerignore", ".env": return .shell
        case "package.json", "tsconfig.json", "jsconfig.json": return .json
        default: break
        }

        // Match by extension
        switch ext {
        // Web
        case "js", "mjs", "cjs": return .javascript
        case "jsx": return .jsx
        case "ts", "mts", "cts": return .typescript
        case "tsx": return .tsx
        case "html", "htm": return .html
        case "css": return .css
        case "scss", "sass": return .scss
        case "json", "jsonc": return .json
        case "vue": return .vue

        // Systems
        case "swift": return .swift
        case "rs": return .rust
        case "go": return .go
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh": return .cpp
        case "m": return .objectiveC
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "cs": return .csharp

        // Scripting
        case "py", "pyw", "pyi": return .python
        case "rb": return .ruby
        case "php": return .php
        case "lua": return .lua
        case "pl", "pm": return .perl
        case "ex", "exs": return .elixir
        case "erl", "hrl": return .erlang

        // Shell
        case "sh", "bash", "zsh", "fish": return .shell

        // Data / Config
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        case "xml", "plist", "svg": return .xml
        case "sql": return .sql
        case "graphql", "gql": return .graphql

        // Markup
        case "md", "markdown": return .markdown

        // Other
        case "r": return .r
        case "dart": return .dart
        case "zig": return .zig

        default: return .generic
        }
    }
}

// MARK: - Language Definitions

extension LanguageConfig {

    // MARK: JavaScript / TypeScript

    static let javascript = LanguageConfig(
        name: "JavaScript",
        keywords: [
            "break", "case", "catch", "continue", "debugger", "default", "delete", "do",
            "else", "finally", "for", "function", "if", "in", "instanceof", "new", "return",
            "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with",
            "class", "const", "enum", "export", "extends", "import", "super", "implements",
            "interface", "let", "package", "private", "protected", "public", "static", "yield",
            "async", "await", "of", "from", "as", "get", "set",
        ],
        typeKeywords: [
            "Array", "Boolean", "Date", "Error", "Function", "Map", "Number", "Object",
            "Promise", "Proxy", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet",
            "BigInt", "ArrayBuffer", "Float32Array", "Float64Array", "Int8Array",
        ],
        literals: ["true", "false", "null", "undefined", "NaN", "Infinity"],
        stringDelimiters: ["\"", "'"],
        templateStrings: true
    )

    static let jsx = LanguageConfig(
        name: "JSX",
        keywords: javascript.keywords,
        typeKeywords: javascript.typeKeywords,
        literals: javascript.literals,
        stringDelimiters: ["\"", "'"],
        templateStrings: true
    )

    static let typescript = LanguageConfig(
        name: "TypeScript",
        keywords: javascript.keywords.union([
            "type", "namespace", "abstract", "declare", "is", "module", "readonly",
            "keyof", "infer", "unique", "satisfies", "override", "asserts", "out",
        ]),
        typeKeywords: javascript.typeKeywords.union([
            "any", "boolean", "never", "number", "string", "symbol", "unknown", "void",
            "Record", "Partial", "Required", "Readonly", "Pick", "Omit", "Exclude", "Extract",
            "NonNullable", "ReturnType", "Parameters", "InstanceType",
        ]),
        literals: javascript.literals,
        stringDelimiters: ["\"", "'"],
        templateStrings: true
    )

    static let tsx = LanguageConfig(
        name: "TSX",
        keywords: typescript.keywords,
        typeKeywords: typescript.typeKeywords,
        literals: typescript.literals,
        stringDelimiters: ["\"", "'"],
        templateStrings: true
    )

    // MARK: CSS / SCSS

    static let css = LanguageConfig(
        name: "CSS",
        keywords: [
            "important", "keyframes", "media", "supports", "font-face", "charset", "import",
            "namespace", "page", "layer", "container", "scope", "property",
        ],
        typeKeywords: [
            "align", "background", "border", "bottom", "box", "clear", "clip", "color",
            "content", "cursor", "direction", "display", "flex", "float", "font", "grid",
            "height", "justify", "left", "letter", "line", "list", "margin", "max", "min",
            "opacity", "order", "outline", "overflow", "padding", "position", "right",
            "text", "top", "transform", "transition", "vertical", "visibility", "white",
            "width", "word", "z", "animation", "appearance", "aspect", "gap", "place",
            "none", "auto", "inherit", "initial", "unset", "revert",
            "block", "inline", "relative", "absolute", "fixed", "sticky",
            "solid", "dashed", "dotted", "hidden", "visible", "scroll",
            "bold", "italic", "normal", "nowrap", "center", "pointer",
        ],
        literals: [],
        commentLine: [],
        stringDelimiters: ["\"", "'"]
    )

    static let scss = LanguageConfig(
        name: "SCSS",
        keywords: css.keywords.union(["mixin", "include", "extend", "if", "else", "for", "each", "while", "function", "return", "use", "forward"]),
        typeKeywords: css.typeKeywords,
        literals: css.literals,
        commentLine: ["//"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: Swift

    static let swift = LanguageConfig(
        name: "Swift",
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
            "catch", "class", "continue", "convenience", "default", "defer", "deinit", "do",
            "dynamic", "else", "enum", "extension", "fallthrough", "fileprivate", "final",
            "for", "func", "get", "guard", "if", "import", "in", "indirect", "infix", "init",
            "inout", "internal", "is", "isolated", "lazy", "let", "macro", "mutating",
            "nonisolated", "nonmutating", "open", "operator", "optional", "override",
            "postfix", "precedencegroup", "prefix", "private", "protocol", "public", "repeat",
            "required", "rethrows", "return", "set", "some", "static", "struct", "subscript",
            "super", "switch", "throw", "throws", "try", "typealias", "unowned", "var",
            "weak", "where", "while", "willSet", "didSet",
        ],
        typeKeywords: [
            "Int", "Double", "Float", "Bool", "String", "Character", "Array", "Dictionary",
            "Set", "Optional", "Result", "Void", "Never", "Any", "AnyObject", "Self",
            "Error", "Codable", "Hashable", "Equatable", "Comparable", "Identifiable",
            "ObservableObject", "Published", "StateObject", "ObservedObject", "State",
            "Binding", "Environment", "View", "some",
        ],
        literals: ["true", "false", "nil"],
        stringDelimiters: ["\""]
    )

    // MARK: Python

    static let python = LanguageConfig(
        name: "Python",
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
            "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
            "return", "try", "while", "with", "yield", "match", "case", "type",
        ],
        typeKeywords: [
            "int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes",
            "bytearray", "memoryview", "range", "frozenset", "complex", "type", "object",
            "Exception", "ValueError", "TypeError", "KeyError", "IndexError", "AttributeError",
            "RuntimeError", "StopIteration", "GeneratorExit", "SystemExit", "OSError",
            "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted",
            "reversed", "any", "all", "min", "max", "sum", "abs", "round", "isinstance",
            "issubclass", "hasattr", "getattr", "setattr", "super", "property", "classmethod",
            "staticmethod", "dataclass",
        ],
        literals: ["True", "False", "None"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"],
        tripleStringDelimiters: ["\"\"\"", "'''"]
    )

    // MARK: Rust

    static let rust = LanguageConfig(
        name: "Rust",
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match",
            "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct",
            "super", "trait", "type", "unsafe", "use", "where", "while", "yield",
        ],
        typeKeywords: [
            "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
            "u8", "u16", "u32", "u64", "u128", "usize", "str", "String", "Vec", "Box",
            "Option", "Result", "HashMap", "HashSet", "Rc", "Arc", "Cell", "RefCell",
            "Mutex", "RwLock", "Pin", "Future", "Iterator", "Display", "Debug", "Clone",
            "Copy", "Send", "Sync", "Sized", "Drop", "Fn", "FnMut", "FnOnce",
        ],
        literals: ["true", "false"],
        stringDelimiters: ["\""]
    )

    // MARK: Go

    static let go = LanguageConfig(
        name: "Go",
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
            "package", "range", "return", "select", "struct", "switch", "type", "var",
        ],
        typeKeywords: [
            "bool", "byte", "complex64", "complex128", "error", "float32", "float64",
            "int", "int8", "int16", "int32", "int64", "rune", "string",
            "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any", "comparable",
        ],
        literals: ["true", "false", "nil", "iota"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: C / C++

    static let c = LanguageConfig(
        name: "C",
        keywords: [
            "auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
            "extern", "for", "goto", "if", "inline", "register", "restrict", "return",
            "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while",
            "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic", "_Noreturn",
            "_Static_assert", "_Thread_local",
        ],
        typeKeywords: [
            "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void",
            "size_t", "ptrdiff_t", "intptr_t", "uintptr_t", "int8_t", "int16_t", "int32_t",
            "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "FILE", "NULL",
        ],
        literals: ["true", "false", "NULL"],
        stringDelimiters: ["\"", "'"]
    )

    static let cpp = LanguageConfig(
        name: "C++",
        keywords: c.keywords.union([
            "catch", "class", "constexpr", "consteval", "constinit", "co_await", "co_return",
            "co_yield", "decltype", "delete", "dynamic_cast", "explicit", "export", "friend",
            "mutable", "namespace", "new", "noexcept", "operator", "override", "private",
            "protected", "public", "reinterpret_cast", "requires", "static_assert",
            "static_cast", "template", "this", "throw", "try", "typeid", "typename",
            "using", "virtual", "concept", "module", "import",
        ]),
        typeKeywords: c.typeKeywords.union([
            "bool", "wchar_t", "char8_t", "char16_t", "char32_t", "nullptr_t", "auto",
            "string", "vector", "map", "set", "unordered_map", "unordered_set", "array",
            "shared_ptr", "unique_ptr", "weak_ptr", "optional", "variant", "any", "tuple",
            "pair", "span", "string_view",
        ]),
        literals: ["true", "false", "nullptr", "NULL"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: Java / Kotlin / C#

    static let java = LanguageConfig(
        name: "Java",
        keywords: [
            "abstract", "assert", "break", "case", "catch", "class", "const", "continue",
            "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto",
            "if", "implements", "import", "instanceof", "interface", "native", "new",
            "package", "private", "protected", "public", "return", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws", "transient",
            "try", "var", "void", "volatile", "while", "yield", "record", "sealed", "permits",
        ],
        typeKeywords: [
            "boolean", "byte", "char", "double", "float", "int", "long", "short",
            "String", "Integer", "Long", "Double", "Float", "Boolean", "Byte", "Character",
            "Object", "Class", "List", "Map", "Set", "ArrayList", "HashMap", "Optional",
        ],
        literals: ["true", "false", "null"],
        stringDelimiters: ["\"", "'"]
    )

    static let kotlin = LanguageConfig(
        name: "Kotlin",
        keywords: [
            "abstract", "annotation", "as", "break", "by", "catch", "class", "companion",
            "const", "constructor", "continue", "crossinline", "data", "do", "else", "enum",
            "expect", "external", "final", "finally", "for", "fun", "get", "if", "import",
            "in", "infix", "init", "inline", "inner", "interface", "internal", "is", "lateinit",
            "noinline", "object", "open", "operator", "out", "override", "package", "private",
            "protected", "public", "reified", "return", "sealed", "set", "super", "suspend",
            "tailrec", "this", "throw", "try", "typealias", "val", "var", "vararg", "when",
            "where", "while",
        ],
        typeKeywords: [
            "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Short", "String",
            "Unit", "Nothing", "Any", "Array", "List", "Map", "Set", "MutableList",
        ],
        literals: ["true", "false", "null"],
        stringDelimiters: ["\"", "'"]
    )

    static let csharp = LanguageConfig(
        name: "C#",
        keywords: [
            "abstract", "as", "async", "await", "base", "bool", "break", "byte", "case",
            "catch", "char", "checked", "class", "const", "continue", "decimal", "default",
            "delegate", "do", "double", "else", "enum", "event", "explicit", "extern",
            "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in",
            "int", "interface", "internal", "is", "lock", "long", "namespace", "new", "null",
            "object", "operator", "out", "override", "params", "private", "protected",
            "public", "readonly", "record", "ref", "return", "sbyte", "sealed", "short",
            "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw",
            "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using",
            "var", "virtual", "void", "volatile", "while", "yield",
        ],
        typeKeywords: ["String", "Console", "Task", "List", "Dictionary", "IEnumerable"],
        literals: ["true", "false", "null"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: Ruby

    static let ruby = LanguageConfig(
        name: "Ruby",
        keywords: [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
            "else", "elsif", "end", "ensure", "for", "if", "in", "module", "next", "not",
            "or", "redo", "rescue", "retry", "return", "self", "super", "then", "unless",
            "until", "when", "while", "yield", "raise", "require", "require_relative",
            "include", "extend", "attr_reader", "attr_writer", "attr_accessor",
            "private", "protected", "public", "lambda", "proc",
        ],
        typeKeywords: [
            "Array", "Hash", "String", "Integer", "Float", "Symbol", "Regexp", "Range",
            "NilClass", "TrueClass", "FalseClass", "Proc", "IO", "File", "Dir",
        ],
        literals: ["true", "false", "nil"],
        commentLine: ["#"],
        commentBlockStart: "=begin",
        commentBlockEnd: "=end",
        stringDelimiters: ["\"", "'"]
    )

    // MARK: PHP

    static let php = LanguageConfig(
        name: "PHP",
        keywords: [
            "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
            "clone", "const", "continue", "declare", "default", "die", "do", "echo", "else",
            "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch",
            "endwhile", "eval", "exit", "extends", "final", "finally", "fn", "for", "foreach",
            "function", "global", "goto", "if", "implements", "include", "include_once",
            "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace",
            "new", "or", "print", "private", "protected", "public", "readonly", "require",
            "require_once", "return", "static", "switch", "throw", "trait", "try", "unset",
            "use", "var", "while", "xor", "yield", "enum",
        ],
        literals: ["true", "false", "null", "TRUE", "FALSE", "NULL"],
        commentLine: ["//", "#"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: Shell

    static let shell = LanguageConfig(
        name: "Shell",
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
            "case", "esac", "in", "function", "select", "return", "exit", "break",
            "continue", "local", "export", "readonly", "declare", "typeset", "unset",
            "source", "alias", "unalias", "set", "shift", "trap", "eval", "exec",
        ],
        typeKeywords: [
            "echo", "printf", "read", "cd", "pwd", "ls", "cp", "mv", "rm", "mkdir",
            "cat", "grep", "sed", "awk", "find", "sort", "uniq", "wc", "head", "tail",
            "chmod", "chown", "curl", "wget", "tar", "gzip", "ssh", "git",
        ],
        literals: ["true", "false"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    // MARK: SQL

    static let sql = LanguageConfig(
        name: "SQL",
        keywords: [
            "select", "from", "where", "and", "or", "not", "in", "is", "null", "as",
            "on", "join", "left", "right", "inner", "outer", "cross", "full", "natural",
            "insert", "into", "values", "update", "set", "delete", "create", "alter", "drop",
            "table", "index", "view", "database", "schema", "if", "exists", "primary", "key",
            "foreign", "references", "unique", "check", "default", "constraint", "cascade",
            "order", "by", "group", "having", "limit", "offset", "union", "all", "distinct",
            "between", "like", "case", "when", "then", "else", "end", "asc", "desc",
            "count", "sum", "avg", "min", "max", "coalesce", "nullif", "cast",
            "begin", "commit", "rollback", "transaction", "grant", "revoke", "with",
            // uppercase variants
            "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL", "AS",
            "ON", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "INSERT", "INTO", "VALUES",
            "UPDATE", "SET", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "INDEX",
            "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "UNION", "ALL", "DISTINCT",
            "BETWEEN", "LIKE", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY", "KEY",
            "BEGIN", "COMMIT", "ROLLBACK", "WITH", "EXISTS", "COUNT", "SUM", "AVG",
        ],
        typeKeywords: [
            "int", "integer", "smallint", "bigint", "decimal", "numeric", "float", "real",
            "double", "precision", "char", "varchar", "text", "blob", "date", "time",
            "timestamp", "datetime", "boolean", "serial", "uuid", "json", "jsonb", "xml",
            "INT", "INTEGER", "VARCHAR", "TEXT", "BOOLEAN", "TIMESTAMP", "JSON", "UUID",
        ],
        literals: ["true", "false", "null", "TRUE", "FALSE", "NULL"],
        commentLine: ["--"],
        stringDelimiters: ["'"]
    )

    // MARK: YAML / TOML

    static let yaml = LanguageConfig(
        name: "YAML",
        keywords: [],
        literals: ["true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let toml = LanguageConfig(
        name: "TOML",
        keywords: [],
        literals: ["true", "false"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    // MARK: HTML / XML / Vue

    static let html = LanguageConfig(
        name: "HTML",
        keywords: [],
        commentLine: [],
        commentBlockStart: "<!--",
        commentBlockEnd: "-->",
        stringDelimiters: ["\"", "'"]
    )

    static let xml = html

    static let vue = LanguageConfig(
        name: "Vue",
        keywords: typescript.keywords,
        typeKeywords: typescript.typeKeywords,
        literals: typescript.literals,
        commentLine: ["//"],
        stringDelimiters: ["\"", "'"],
        templateStrings: true
    )

    // MARK: JSON

    static let json = LanguageConfig(
        name: "JSON",
        keywords: [],
        literals: ["true", "false", "null"],
        commentLine: [],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\""]
    )

    // MARK: Lua / Perl / Elixir / Erlang

    static let lua = LanguageConfig(
        name: "Lua",
        keywords: [
            "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
            "in", "local", "not", "or", "repeat", "return", "then", "until", "while",
        ],
        literals: ["true", "false", "nil"],
        commentLine: ["--"],
        commentBlockStart: "--[[",
        commentBlockEnd: "]]",
        stringDelimiters: ["\"", "'"]
    )

    static let perl = LanguageConfig(
        name: "Perl",
        keywords: [
            "chomp", "chop", "chr", "crypt", "die", "do", "dump", "each", "else", "elsif",
            "eval", "exec", "exit", "for", "foreach", "goto", "if", "last", "local", "my",
            "next", "no", "our", "print", "redo", "require", "return", "say", "sub", "unless",
            "until", "use", "when", "while",
        ],
        literals: ["undef"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let elixir = LanguageConfig(
        name: "Elixir",
        keywords: [
            "after", "alias", "and", "case", "catch", "cond", "def", "defcallback",
            "defexception", "defimpl", "defmacro", "defmodule", "defp", "defprotocol",
            "defstruct", "do", "else", "end", "fn", "for", "if", "import", "in", "not",
            "or", "quote", "raise", "receive", "require", "rescue", "try", "unless",
            "unquote", "use", "when", "with",
        ],
        literals: ["true", "false", "nil"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let erlang = LanguageConfig(
        name: "Erlang",
        keywords: [
            "after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr", "bxor",
            "case", "catch", "cond", "div", "end", "fun", "if", "let", "not", "of", "or",
            "orelse", "receive", "rem", "try", "when", "xor",
        ],
        literals: ["true", "false", "undefined"],
        commentLine: ["%"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\""]
    )

    // MARK: Other

    static let objectiveC = LanguageConfig(
        name: "Objective-C",
        keywords: c.keywords.union(["id", "self", "super", "nil", "YES", "NO", "SEL", "IMP", "BOOL"]),
        typeKeywords: c.typeKeywords.union(["NSObject", "NSString", "NSArray", "NSDictionary", "NSNumber", "NSInteger", "CGFloat"]),
        literals: ["YES", "NO", "nil", "Nil", "NULL", "true", "false"],
        stringDelimiters: ["\"", "'"]
    )

    static let r = LanguageConfig(
        name: "R",
        keywords: [
            "if", "else", "repeat", "while", "function", "for", "in", "next", "break",
            "return", "library", "require", "source",
        ],
        literals: ["TRUE", "FALSE", "NULL", "NA", "NaN", "Inf", "T", "F"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let dart = LanguageConfig(
        name: "Dart",
        keywords: [
            "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class",
            "const", "continue", "covariant", "default", "deferred", "do", "dynamic", "else",
            "enum", "export", "extends", "extension", "external", "factory", "final", "finally",
            "for", "get", "if", "implements", "import", "in", "is", "late", "library", "mixin",
            "new", "null", "on", "operator", "part", "required", "rethrow", "return", "sealed",
            "set", "show", "static", "super", "switch", "sync", "this", "throw", "try",
            "typedef", "var", "void", "while", "with", "yield",
        ],
        literals: ["true", "false", "null"],
        stringDelimiters: ["\"", "'"]
    )

    static let zig = LanguageConfig(
        name: "Zig",
        keywords: [
            "align", "allowzero", "and", "asm", "async", "await", "break", "catch",
            "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error",
            "export", "extern", "fn", "for", "if", "inline", "noalias", "nosuspend",
            "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch",
            "test", "threadlocal", "try", "union", "unreachable", "var", "volatile", "while",
        ],
        literals: ["true", "false", "null", "undefined"],
        stringDelimiters: ["\""]
    )

    static let graphql = LanguageConfig(
        name: "GraphQL",
        keywords: [
            "type", "input", "interface", "union", "enum", "scalar", "schema", "query",
            "mutation", "subscription", "fragment", "on", "directive", "extend", "implements",
        ],
        literals: ["true", "false", "null"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\""]
    )

    static let markdown = LanguageConfig(
        name: "Markdown",
        keywords: [],
        literals: [],
        commentLine: [],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: []
    )

    static let makefile = LanguageConfig(
        name: "Makefile",
        keywords: ["ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "include", "define", "endef", "override", "export", "unexport", "vpath"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let dockerfile = LanguageConfig(
        name: "Dockerfile",
        keywords: ["FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL", "MAINTAINER"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\"", "'"]
    )

    static let cmake = LanguageConfig(
        name: "CMake",
        keywords: ["if", "else", "elseif", "endif", "foreach", "endforeach", "while", "endwhile", "function", "endfunction", "macro", "endmacro", "return", "set", "unset", "option", "message", "add_executable", "add_library", "target_link_libraries", "find_package", "include", "project", "cmake_minimum_required"],
        commentLine: ["#"],
        commentBlockStart: nil,
        commentBlockEnd: nil,
        stringDelimiters: ["\""]
    )

    // MARK: Generic fallback

    static let generic = LanguageConfig(
        name: "Generic",
        keywords: [
            "if", "else", "for", "while", "return", "break", "continue", "switch", "case",
            "default", "import", "export", "from", "class", "function", "func", "def", "var",
            "let", "const", "new", "this", "self", "super", "try", "catch", "throw", "async",
            "await", "yield", "true", "false", "null", "nil", "None",
        ],
        commentLine: ["//", "#"],
        stringDelimiters: ["\"", "'"]
    )
}
