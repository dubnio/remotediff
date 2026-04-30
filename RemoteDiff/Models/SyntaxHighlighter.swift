import Foundation

// MARK: - Syntax Token

/// The kind of syntax element a token represents.
enum SyntaxTokenKind: Equatable {
    case plain
    case keyword
    case type
    case literal
    case string
    case comment
    case number
}

/// A single token from syntax highlighting a line of code.
struct SyntaxToken: Equatable {
    let text: String
    let kind: SyntaxTokenKind
}

// MARK: - Tokenization Result

/// Result of tokenizing a single line, including multi-line carry-over state
/// (block comments and triple-quoted strings).
struct TokenizeResult {
    let tokens: [SyntaxToken]
    let inBlockComment: Bool
    /// If non-nil, the line ended inside a triple-quoted string; the value is the
    /// open delimiter (e.g. `"""` or `'''`) used to look for the matching close.
    let inTripleString: String?

    init(tokens: [SyntaxToken], inBlockComment: Bool, inTripleString: String? = nil) {
        self.tokens = tokens
        self.inBlockComment = inBlockComment
        self.inTripleString = inTripleString
    }
}

// MARK: - Syntax Highlighter

/// A pure-logic syntax highlighter that tokenizes a line of code based on a LanguageConfig.
/// No UI dependencies — produces `[SyntaxToken]` that views can render with colors.
enum SyntaxHighlighter {

    /// Tokenize a line with default state (not inside a block comment or triple string).
    static func tokenize(line: String, language: LanguageConfig) -> [SyntaxToken] {
        tokenizeWithState(line: line, language: language, inBlockComment: false, inTripleString: nil).tokens
    }

    /// Tokenize a line with explicit block-comment state tracking.
    static func tokenizeWithState(
        line: String,
        language: LanguageConfig,
        inBlockComment: Bool
    ) -> TokenizeResult {
        tokenizeWithState(line: line, language: language, inBlockComment: inBlockComment, inTripleString: nil)
    }

    /// Tokenize a line with explicit block-comment and triple-string state tracking.
    static func tokenizeWithState(
        line: String,
        language: LanguageConfig,
        inBlockComment: Bool,
        inTripleString: String?
    ) -> TokenizeResult {
        guard !line.isEmpty else {
            return TokenizeResult(tokens: [], inBlockComment: inBlockComment, inTripleString: inTripleString)
        }

        var tokens: [SyntaxToken] = []
        let chars = Array(line)
        let count = chars.count
        var i = 0
        var stillInBlock = inBlockComment
        var stillInTriple = inTripleString

        // If we're inside a triple-quoted string from a previous line, consume until
        // the matching closing delimiter.
        if let openDelim = stillInTriple {
            if let endIdx = findSubstring(chars, from: 0, target: openDelim) {
                let endPos = endIdx + openDelim.count
                tokens.append(SyntaxToken(text: String(chars[0..<endPos]), kind: .string))
                i = endPos
                stillInTriple = nil
            } else {
                // Entire line is still inside the triple-quoted string
                return TokenizeResult(
                    tokens: [SyntaxToken(text: line, kind: .string)],
                    inBlockComment: false,
                    inTripleString: openDelim
                )
            }
        }

        // If we're inside a block comment from a previous line, consume until end marker.
        if stillInBlock {
            if let endMarker = language.commentBlockEnd {
                if let endIdx = findSubstring(chars, from: i, target: endMarker) {
                    let endPos = endIdx + endMarker.count
                    tokens.append(SyntaxToken(text: String(chars[i..<endPos]), kind: .comment))
                    i = endPos
                    stillInBlock = false
                } else {
                    // Entire remainder of line is still inside block comment
                    tokens.append(SyntaxToken(text: String(chars[i...]), kind: .comment))
                    return TokenizeResult(
                        tokens: tokens,
                        inBlockComment: true,
                        inTripleString: nil
                    )
                }
            } else {
                // Language has no block comment end — shouldn't happen, but treat as plain
                stillInBlock = false
            }
        }

        // Main tokenization loop
        var plainBuffer = ""

        func flushPlain() {
            if !plainBuffer.isEmpty {
                tokens.append(SyntaxToken(text: plainBuffer, kind: .plain))
                plainBuffer = ""
            }
        }

        while i < count {
            // 1. Check for line comment
            if let commentToken = tryLineComment(chars, from: i, language: language) {
                flushPlain()
                tokens.append(commentToken)
                i = count // line comment consumes rest of line
                continue
            }

            // 2. Check for block comment start
            if let (token, endPos, openStill) = tryBlockComment(chars, from: i, language: language) {
                flushPlain()
                tokens.append(token)
                i = endPos
                if openStill { stillInBlock = true; break }
                continue
            }

            // 3. Check for triple-quoted string (must be checked before single-char strings
            //    so e.g. `"""` isn't read as two empty strings).
            if let (token, endPos, openDelim) = tryTripleString(chars, from: i, language: language) {
                flushPlain()
                tokens.append(token)
                i = endPos
                if let openDelim = openDelim { stillInTriple = openDelim; break }
                continue
            }

            // 4. Check for string
            if let (token, endPos) = tryString(chars, from: i, language: language) {
                flushPlain()
                tokens.append(token)
                i = endPos
                continue
            }

            // 5. Check for number (must not be preceded by a word char)
            if chars[i].isNumber && !isPrecededByWordChar(chars, at: i) {
                flushPlain()
                let (token, endPos) = consumeNumber(chars, from: i)
                tokens.append(token)
                i = endPos
                continue
            }

            // 6. Check for word (identifiers / keywords / types / literals)
            if isWordStart(chars[i]) {
                flushPlain()
                let (word, endPos) = consumeWord(chars, from: i)
                let kind = classifyWord(word, language: language)
                tokens.append(SyntaxToken(text: word, kind: kind))
                i = endPos
                continue
            }

            // 7. Default: plain character (operators, punctuation, whitespace)
            plainBuffer.append(chars[i])
            i += 1
        }

        flushPlain()

        return TokenizeResult(tokens: tokens, inBlockComment: stillInBlock, inTripleString: stillInTriple)
    }

    // MARK: - Line Comment

    private static func tryLineComment(
        _ chars: [Character], from i: Int, language: LanguageConfig
    ) -> SyntaxToken? {
        for prefix in language.commentLine {
            let prefixChars = Array(prefix)
            if i + prefixChars.count <= chars.count {
                let slice = Array(chars[i..<(i + prefixChars.count)])
                if slice == prefixChars {
                    let text = String(chars[i...])
                    return SyntaxToken(text: text, kind: .comment)
                }
            }
        }
        return nil
    }

    // MARK: - Block Comment

    /// Returns (token, newIndex, stillOpen) or nil.
    private static func tryBlockComment(
        _ chars: [Character], from i: Int, language: LanguageConfig
    ) -> (SyntaxToken, Int, Bool)? {
        guard let startMarker = language.commentBlockStart,
              let endMarker = language.commentBlockEnd else { return nil }

        let startChars = Array(startMarker)
        guard i + startChars.count <= chars.count else { return nil }

        let slice = Array(chars[i..<(i + startChars.count)])
        guard slice == startChars else { return nil }

        // Found block comment start — look for end
        let searchFrom = i + startChars.count
        if let endIdx = findSubstring(chars, from: searchFrom, target: endMarker) {
            let endPos = endIdx + endMarker.count
            let text = String(chars[i..<endPos])
            return (SyntaxToken(text: text, kind: .comment), endPos, false)
        } else {
            // Block comment continues beyond this line
            let text = String(chars[i...])
            return (SyntaxToken(text: text, kind: .comment), chars.count, true)
        }
    }

    // MARK: - Triple-Quoted String

    /// Returns (token, newIndex, openDelimIfStillOpen) or nil.
    /// If `openDelimIfStillOpen` is non-nil, the string was not closed on this line.
    private static func tryTripleString(
        _ chars: [Character], from i: Int, language: LanguageConfig
    ) -> (SyntaxToken, Int, String?)? {
        for delim in language.tripleStringDelimiters {
            let delimChars = Array(delim)
            guard i + delimChars.count <= chars.count else { continue }
            let slice = Array(chars[i..<(i + delimChars.count)])
            guard slice == delimChars else { continue }

            // Found triple-string opener — look for matching closer.
            let searchFrom = i + delimChars.count
            if let endIdx = findSubstring(chars, from: searchFrom, target: delim) {
                let endPos = endIdx + delimChars.count
                let text = String(chars[i..<endPos])
                return (SyntaxToken(text: text, kind: .string), endPos, nil)
            } else {
                // Triple string continues past end of line
                let text = String(chars[i...])
                return (SyntaxToken(text: text, kind: .string), chars.count, delim)
            }
        }
        return nil
    }

    // MARK: - String

    private static func tryString(
        _ chars: [Character], from i: Int, language: LanguageConfig
    ) -> (SyntaxToken, Int)? {
        let ch = chars[i]

        // Check backtick template strings
        if ch == "`" && language.templateStrings {
            return consumeString(chars, from: i, delimiter: "`")
        }

        // Check configured string delimiters
        guard language.stringDelimiters.contains(ch) else { return nil }
        return consumeString(chars, from: i, delimiter: ch)
    }

    private static func consumeString(
        _ chars: [Character], from i: Int, delimiter: Character
    ) -> (SyntaxToken, Int) {
        var j = i + 1
        while j < chars.count {
            if chars[j] == "\\" {
                j += 2 // skip escaped character
                continue
            }
            if chars[j] == delimiter {
                j += 1
                let text = String(chars[i..<j])
                return (SyntaxToken(text: text, kind: .string), j)
            }
            j += 1
        }
        // Unterminated string — consume to end of line
        let text = String(chars[i...])
        return (SyntaxToken(text: text, kind: .string), chars.count)
    }

    // MARK: - Number

    private static func consumeNumber(_ chars: [Character], from i: Int) -> (SyntaxToken, Int) {
        var j = i
        var sawDot = false
        while j < chars.count {
            if chars[j].isNumber {
                j += 1
            } else if chars[j] == "." && !sawDot && j + 1 < chars.count && chars[j + 1].isNumber {
                sawDot = true
                j += 1
            } else {
                break
            }
        }
        let text = String(chars[i..<j])
        return (SyntaxToken(text: text, kind: .number), j)
    }

    // MARK: - Word

    private static func isWordStart(_ ch: Character) -> Bool {
        ch.isLetter || ch == "_"
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    private static func consumeWord(_ chars: [Character], from i: Int) -> (String, Int) {
        var j = i
        while j < chars.count && isWordChar(chars[j]) {
            j += 1
        }
        return (String(chars[i..<j]), j)
    }

    private static func classifyWord(_ word: String, language: LanguageConfig) -> SyntaxTokenKind {
        if language.keywords.contains(word) { return .keyword }
        if language.typeKeywords.contains(word) { return .type }
        if language.literals.contains(word) { return .literal }
        return .plain
    }

    // MARK: - Helpers

    private static func isPrecededByWordChar(_ chars: [Character], at i: Int) -> Bool {
        guard i > 0 else { return false }
        return isWordChar(chars[i - 1])
    }

    private static func findSubstring(_ chars: [Character], from start: Int, target: String) -> Int? {
        let targetChars = Array(target)
        guard targetChars.count > 0 else { return nil }
        let limit = chars.count - targetChars.count
        guard start <= limit else { return nil }
        for pos in start...limit {
            if Array(chars[pos..<(pos + targetChars.count)]) == targetChars {
                return pos
            }
        }
        return nil
    }
}
