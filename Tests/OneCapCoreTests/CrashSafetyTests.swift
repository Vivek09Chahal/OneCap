import Foundation
import Testing
@testable import OneCapCore

@Test func invalidAgentJSONReturnsAnErrorWithoutWritingToThePipe() async throws {
    let pipe = Pipe()
    defer {
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
    for invalid: ACPMessage in [
        ACPMessage(object: ["params": ["value": Date()]]),
        ACPMessage(object: ["params": ["value": Double.nan]]),
    ] {
        let error = await withCheckedContinuation { continuation in
            ACPMessageWriter().write(invalid, to: pipe.fileHandleForWriting) {
                continuation.resume(returning: $0)
            }
        }
        #expect(error.localizedDescription.contains("invalid JSON"))
    }
    try pipe.fileHandleForWriting.close()
    #expect(try pipe.fileHandleForReading.readToEnd()?.isEmpty != false)
}

@Test func diffRangesAndContextStayWithinBothSnapshots() {
    // Repeated lines exercise ambiguous matches, deletions at the beginning,
    // insertions at the end, and adjacent independent hunks.
    var snapshots = [""]
    for length in 1...4 {
        for bits in 0..<(1 << length) {
            snapshots.append((0..<length).map { bits & (1 << $0) == 0 ? "a\n" : "b\n" }.joined())
        }
    }
    for before in snapshots {
        for after in snapshots {
            let file = FileEdit(path: "test.txt", before: before, after: after,
                permissions: nil, additions: 0, deletions: 0, diff: "")
            let old = FileTextDiff.lines(before)
            let new = FileTextDiff.lines(after)
            for hunk in file.hunks {
                #expect(hunk.oldRange.lowerBound >= hunk.leadingContext.count)
                #expect(hunk.newRange.lowerBound >= hunk.leadingContext.count)
                #expect(hunk.oldRange.upperBound + hunk.trailingContext.count <= old.count)
                #expect(hunk.newRange.upperBound + hunk.trailingContext.count <= new.count)
                #expect(Array(old[hunk.oldRange]) == hunk.oldLines)
                #expect(Array(new[hunk.newRange]) == hunk.newLines)
            }
            for row in FileReviewLayout(file: file).rows {
                if let line = row.oldLine { #expect((1...max(1, old.count)).contains(line)) }
                if let line = row.newLine { #expect((1...max(1, new.count)).contains(line)) }
            }
        }
    }
}

@Test func staleSlashQueryDoesNotIndexPastAShortenedDraft() throws {
    let query = try #require(ComposerSlashQuery.active(in: "Some text /model"))
    #expect(query.occurrencePrefix(in: "") == "")
    #expect(query.occurrencePrefix(in: "short") == "")
    #expect(ComposerSlashQuery.active(in: "/model", at: "long obsolete draft".endIndex) == nil)
}
