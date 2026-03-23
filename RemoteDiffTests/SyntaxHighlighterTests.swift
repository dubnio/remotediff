import XCTest
@testable import RemoteDiff

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - Basic Tokenization

    func testPlainTextReturnsOneToken() {
        let tokens = SyntaxHighlighter.tokenize(line: "hello world", language: .generic)
        let combined = tokens.map(\.text).joined()
        XCTAssertEqual(combined, "hello world")
    }

    func testEmptyLineReturnsEmpty() {
        let tokens = SyntaxHighlighter.tokenize(line: "", language: .generic)
        XCTAssertTrue(tokens.isEmpty)
    }

    // MARK: - Keywords

    func testSwiftKeywords() {
        let tokens = SyntaxHighlighter.tokenize(line: "let x = 5", language: .swift)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertEqual(keywords.count, 1)
        XCTAssertEqual(keywords[0].text, "let")
    }

    func testMultipleKeywords() {
        let tokens = SyntaxHighlighter.tokenize(line: "if let x = y else", language: .swift)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertEqual(keywords.count, 3) // if, let, else
    }

    func testKeywordNotInMiddleOfWord() {
        // "letter" starts with "let" but shouldn't be a keyword
        let tokens = SyntaxHighlighter.tokenize(line: "letter", language: .swift)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertTrue(keywords.isEmpty)
    }

    // MARK: - Type Keywords

    func testTypeKeywords() {
        let tokens = SyntaxHighlighter.tokenize(line: "var x: String = \"\"", language: .swift)
        let types = tokens.filter { $0.kind == .type }
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(types[0].text, "String")
    }

    // MARK: - Literals

    func testLiterals() {
        let tokens = SyntaxHighlighter.tokenize(line: "return true", language: .swift)
        let literals = tokens.filter { $0.kind == .literal }
        XCTAssertEqual(literals.count, 1)
        XCTAssertEqual(literals[0].text, "true")
    }

    func testNilLiteral() {
        let tokens = SyntaxHighlighter.tokenize(line: "let x = nil", language: .swift)
        let literals = tokens.filter { $0.kind == .literal }
        XCTAssertEqual(literals.count, 1)
        XCTAssertEqual(literals[0].text, "nil")
    }

    // MARK: - Strings

    func testDoubleQuotedString() {
        let tokens = SyntaxHighlighter.tokenize(line: "let s = \"hello\"", language: .swift)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings[0].text, "\"hello\"")
    }

    func testSingleQuotedString() {
        let tokens = SyntaxHighlighter.tokenize(line: "let s = 'hello'", language: .javascript)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings[0].text, "'hello'")
    }

    func testStringWithEscapedQuote() {
        let tokens = SyntaxHighlighter.tokenize(line: #"let s = "say \"hi\"""#, language: .swift)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings[0].text, #""say \"hi\"""#)
    }

    func testUnterminatedStringGoesToEndOfLine() {
        let tokens = SyntaxHighlighter.tokenize(line: "let s = \"open", language: .swift)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings[0].text, "\"open")
    }

    // MARK: - Line Comments

    func testLineComment() {
        let tokens = SyntaxHighlighter.tokenize(line: "x = 1 // comment", language: .swift)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].text, "// comment")
    }

    func testHashComment() {
        let tokens = SyntaxHighlighter.tokenize(line: "x = 1 # comment", language: .python)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].text, "# comment")
    }

    func testFullLineComment() {
        let tokens = SyntaxHighlighter.tokenize(line: "// this is all comment", language: .swift)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
        XCTAssertEqual(tokens[0].text, "// this is all comment")
    }

    func testCommentInsideStringNotTreatedAsComment() {
        let tokens = SyntaxHighlighter.tokenize(line: "let s = \"// not a comment\"", language: .swift)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertTrue(comments.isEmpty)
    }

    // MARK: - Block Comments

    func testBlockCommentOnSingleLine() {
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "x /* comment */ y", language: .swift, inBlockComment: false
        )
        let comments = result.tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].text, "/* comment */")
        XCTAssertFalse(result.inBlockComment)
    }

    func testBlockCommentStartsButDoesntEnd() {
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "x /* open comment", language: .swift, inBlockComment: false
        )
        let comments = result.tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].text, "/* open comment")
        XCTAssertTrue(result.inBlockComment)
    }

    func testContinuedBlockComment() {
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "still in comment */ code", language: .swift, inBlockComment: true
        )
        let comments = result.tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].text, "still in comment */")
        XCTAssertFalse(result.inBlockComment)
    }

    func testEntireLineInBlockComment() {
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "all comment here", language: .swift, inBlockComment: true
        )
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].kind, .comment)
        XCTAssertTrue(result.inBlockComment)
    }

    // MARK: - Numbers

    func testIntegerNumber() {
        let tokens = SyntaxHighlighter.tokenize(line: "let x = 42", language: .swift)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertEqual(numbers.count, 1)
        XCTAssertEqual(numbers[0].text, "42")
    }

    func testFloatingPointNumber() {
        let tokens = SyntaxHighlighter.tokenize(line: "let pi = 3.14", language: .swift)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertEqual(numbers.count, 1)
        XCTAssertEqual(numbers[0].text, "3.14")
    }

    func testNumberNotInsideWord() {
        // "x2" should not produce a number token for "2"
        let tokens = SyntaxHighlighter.tokenize(line: "x2", language: .swift)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertTrue(numbers.isEmpty)
    }

    // MARK: - Full Line Reconstruction

    func testTokensCoverEntireLine() {
        let line = "func greet(_ name: String) -> Bool { return true }"
        let tokens = SyntaxHighlighter.tokenize(line: line, language: .swift)
        let reconstructed = tokens.map(\.text).joined()
        XCTAssertEqual(reconstructed, line)
    }

    func testTokensCoverLineWithComment() {
        let line = "let x = 42 // the answer"
        let tokens = SyntaxHighlighter.tokenize(line: line, language: .swift)
        let reconstructed = tokens.map(\.text).joined()
        XCTAssertEqual(reconstructed, line)
    }

    func testTokensCoverLineWithString() {
        let line = #"print("hello, world")"#
        let tokens = SyntaxHighlighter.tokenize(line: line, language: .swift)
        let reconstructed = tokens.map(\.text).joined()
        XCTAssertEqual(reconstructed, line)
    }

    // MARK: - Python Specifics

    func testPythonKeywords() {
        let tokens = SyntaxHighlighter.tokenize(line: "def foo():", language: .python)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertEqual(keywords.count, 1)
        XCTAssertEqual(keywords[0].text, "def")
    }

    func testPythonNoBlockComments() {
        // Python has no /* */ block comments
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "x /* not a comment */", language: .python, inBlockComment: false
        )
        let comments = result.tokens.filter { $0.kind == .comment }
        XCTAssertTrue(comments.isEmpty)
    }

    // MARK: - JavaScript Template Strings

    func testBacktickString() {
        let tokens = SyntaxHighlighter.tokenize(line: "const s = `hello`", language: .javascript)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings[0].text, "`hello`")
    }

    // MARK: - Edge Cases

    func testLeadingWhitespacePreserved() {
        let tokens = SyntaxHighlighter.tokenize(line: "    let x = 1", language: .swift)
        let reconstructed = tokens.map(\.text).joined()
        XCTAssertEqual(reconstructed, "    let x = 1")
        XCTAssertEqual(tokens[0].kind, .plain)
    }

    func testOperatorsArePlain() {
        let tokens = SyntaxHighlighter.tokenize(line: "x + y = z", language: .swift)
        let plains = tokens.filter { $0.kind == .plain }
        // operators and spaces should be plain
        XCTAssertTrue(plains.contains { $0.text.contains("+") })
    }

    func testLanguageWithNoBlockComments() {
        let result = SyntaxHighlighter.tokenizeWithState(
            line: "echo hello", language: .shell, inBlockComment: false
        )
        XCTAssertFalse(result.inBlockComment)
    }
}
