import Foundation

enum JSONCError: LocalizedError {
    case notAnObject
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "The top level of opencode.json must be a JSON object."
        case .malformed(let detail):
            return "opencode.json is not valid JSON: \(detail)"
        }
    }
}

/// opencode.json accepts JSONC (comments and trailing commas). JSONSerialization
/// does not, so comments are stripped before parsing. Unknown keys survive a
/// round trip because the document is edited as an untyped dictionary.
enum JSONC {
    static func object(from data: Data) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        let cleaned = strip(text)
        do {
            let any = try JSONSerialization.jsonObject(with: Data(cleaned.utf8), options: [.fragmentsAllowed])
            guard let object = any as? [String: Any] else { throw JSONCError.notAnObject }
            return object
        } catch let error as JSONCError {
            throw error
        } catch {
            throw JSONCError.malformed(error.localizedDescription)
        }
    }

    static func data(_ object: [String: Any]) throws -> Data {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try JSONSerialization.data(withJSONObject: object, options: options)
        data.append(0x0A)
        return data
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return text == "true" }
        return nil
    }

    static func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [String] { return array }
        if let array = value as? [Any] { return array.compactMap { $0 as? String } }
        if let single = value as? String { return [single] }
        return []
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dict {
            if let string = raw as? String { result[key] = string }
            else if let number = raw as? NSNumber { result[key] = number.stringValue }
        }
        return result
    }

    /// Removes `//` and `/* */` comments while respecting string literals,
    /// then drops commas that sit directly before a closing brace or bracket.
    static func strip(_ input: String) -> String {
        let chars = Array(input)
        var out = String()
        out.reserveCapacity(chars.count)
        var index = 0
        var inString = false
        var escaped = false

        while index < chars.count {
            let char = chars[index]

            if inString {
                out.append(char)
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                index += 1
                continue
            }

            if char == "\"" {
                inString = true
                out.append(char)
                index += 1
                continue
            }

            if char == "/", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "/" {
                    index += 2
                    while index < chars.count && chars[index] != "\n" { index += 1 }
                    continue
                }
                if next == "*" {
                    index += 2
                    while index + 1 < chars.count && !(chars[index] == "*" && chars[index + 1] == "/") {
                        index += 1
                    }
                    index = min(index + 2, chars.count)
                    continue
                }
            }

            out.append(char)
            index += 1
        }

        return removeTrailingCommas(out)
    }

    private static func removeTrailingCommas(_ input: String) -> String {
        let chars = Array(input)
        var out = String()
        out.reserveCapacity(chars.count)
        var index = 0
        var inString = false
        var escaped = false

        while index < chars.count {
            let char = chars[index]

            if inString {
                out.append(char)
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                index += 1
                continue
            }

            if char == "\"" {
                inString = true
                out.append(char)
                index += 1
                continue
            }

            if char == "," {
                var lookahead = index + 1
                while lookahead < chars.count, chars[lookahead].isWhitespace { lookahead += 1 }
                if lookahead < chars.count, chars[lookahead] == "}" || chars[lookahead] == "]" {
                    index += 1
                    continue
                }
            }

            out.append(char)
            index += 1
        }

        return out
    }
}
