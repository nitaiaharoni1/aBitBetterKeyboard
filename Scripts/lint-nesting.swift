import Foundation
import SwiftParser
import SwiftSyntax

final class NestingVisitor: SyntaxAnyVisitor {
    let limit: Int
    let converter: SourceLocationConverter
    var violations = 0
    var depth = 0

    init(limit: Int, file: String, tree: SourceFileSyntax) {
        self.limit = limit
        converter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    func addsDepth(_ node: Syntax) -> Bool {
        switch node.kind {
        case .ifExpr:
            return node.parent?.is(IfExprSyntax.self) != true
        case .forStmt, .whileStmt, .repeatStmt, .switchExpr, .guardStmt,
            .doStmt, .deferStmt, .closureExpr:
            return true
        default:
            return false
        }
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if addsDepth(node) {
            depth += 1
            if depth == limit + 1 {
                let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
                print(
                    "\(location.file):\(location.line):\(location.column): error: "
                        + "Control-flow or closure nesting exceeds \(limit) levels (control_flow_nesting)")
                violations += 1
            }
        }
        return .visitChildren
    }

    override func visitAnyPost(_ node: Syntax) {
        if addsDepth(node) {
            depth -= 1
        }
    }
}

guard CommandLine.arguments.count >= 3,
    let limit = Int(CommandLine.arguments[1]), limit > 0
else {
    fputs("Usage: lint-nesting.swift <positive-depth-limit> <files...>\n", stderr)
    exit(1)
}

var violations = 0
for file in CommandLine.arguments.dropFirst(2) {
    do {
        let source = try String(contentsOfFile: file, encoding: .utf8)
        let tree = Parser.parse(source: source)
        guard !tree.hasError else {
            fputs("\(file):1:1: error: Cannot check nesting: invalid Swift syntax\n", stderr)
            violations += 1
            continue
        }
        let visitor = NestingVisitor(limit: limit, file: file, tree: tree)
        visitor.walk(tree)
        violations += visitor.violations
    } catch {
        fputs("\(file):1:1: error: \(error)\n", stderr)
        violations += 1
    }
}
print("Control-flow nesting: \(violations) violation(s).")
exit(violations == 0 ? 0 : 1)
