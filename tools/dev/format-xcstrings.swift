// Rewrites a string catalog the way Xcode writes it, so scripted edits produce minimal diffs:
// Foundation's pretty-printed JSON with sorted keys, unescaped slashes and no trailing newline.
// Usage: swift tools/dev/format-xcstrings.swift <in.xcstrings> [<out.xcstrings>]
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: format-xcstrings.swift <in> [<out>]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : arguments[1])
let object = try JSONSerialization.jsonObject(with: Data(contentsOf: input))
let data = try JSONSerialization.data(
    withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: output)
