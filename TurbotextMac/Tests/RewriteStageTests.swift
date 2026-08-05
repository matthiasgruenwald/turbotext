import XCTest
@testable import Turbotext

@MainActor
final class RewriteStageTests: XCTestCase {
    private let shortInputLabel = "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt"

    // MARK: - Thresholds (<2 / 2–4 / >=5, ADR 0009)

    func testTranscriptBelowTwoCharactersIsRejectedWithoutRewrite() async throws {
        var rewriteCalled = false
        let stage = RewriteStage { _ in
            rewriteCalled = true
            return RewriteStepResult(text: "ignored", completionLabel: nil)
        }

        for transcript in ["", "a", " a \n"] {
            let outcome = try await stage.run(transcript)
            XCTAssertEqual(outcome, .rejected)
        }
        XCTAssertFalse(rewriteCalled)
    }

    func testTwoToFourCharacterTranscriptIsInsertedRawWithoutRewrite() async throws {
        var rewriteCalled = false
        let stage = RewriteStage { _ in
            rewriteCalled = true
            return RewriteStepResult(text: "ignored", completionLabel: nil)
        }

        for transcript in ["ab", "Nein", "abcd"] {
            let outcome = try await stage.run(transcript)
            XCTAssertEqual(outcome, .rawInsertion(text: transcript, completionLabel: shortInputLabel))
        }
        XCTAssertFalse(rewriteCalled)
    }

    func testFiveCharacterTranscriptReachesRewrite() async throws {
        var rewriteInput: String?
        let stage = RewriteStage { transcript in
            rewriteInput = transcript
            return RewriteStepResult(text: "Danke.", completionLabel: nil)
        }

        let outcome = try await stage.run("Danke")

        XCTAssertEqual(rewriteInput, "Danke")
        XCTAssertEqual(outcome, .rewritten(text: "Danke.", completionLabel: nil))
    }

    // MARK: - Cleaning

    func testInputIsCleanedBeforeTheGates() async throws {
        var rewriteInput: String?
        let stage = RewriteStage { transcript in
            rewriteInput = transcript
            return RewriteStepResult(text: "ignored", completionLabel: nil)
        }

        let rawShort = try await stage.run("  ab \n")
        XCTAssertEqual(rawShort, .rawInsertion(text: "ab", completionLabel: shortInputLabel))

        _ = try await stage.run(" abcde \n")
        XCTAssertEqual(rewriteInput, "abcde")
    }

    func testRewriteResultIsCleaned() async throws {
        let stage = RewriteStage { _ in
            RewriteStepResult(text: "  Ergebnis  \n", completionLabel: nil)
        }

        let outcome = try await stage.run("Hallo Welt")

        XCTAssertEqual(outcome, .rewritten(text: "Ergebnis", completionLabel: nil))
    }

    // MARK: - No-speech sentinel (#180)

    func testSentinelMatchOnRewriteResultIsRejected() async throws {
        var rewriteCalled = false
        let stage = RewriteStage(noSpeechSentinel: "KEINE_AUFNAHME_ERKANNT") { _ in
            rewriteCalled = true
            return RewriteStepResult(text: " KEINE_AUFNAHME_ERKANNT ", completionLabel: nil)
        }

        let outcome = try await stage.run("Hallo Welt")

        XCTAssertTrue(rewriteCalled)
        XCTAssertEqual(outcome, .rejected)
    }

    func testRewriteResultPassesThroughWithoutSentinel() async throws {
        let stage = RewriteStage { _ in
            RewriteStepResult(text: "KEINE_AUFNAHME_ERKANNT", completionLabel: nil)
        }

        let outcome = try await stage.run("Hallo Welt")

        XCTAssertEqual(outcome, .rewritten(text: "KEINE_AUFNAHME_ERKANNT", completionLabel: nil))
    }

    // MARK: - Completion labels

    func testRewrittenOutcomeCarriesTheRewriteCompletionLabel() async throws {
        let stage = RewriteStage { _ in
            RewriteStepResult(text: "Verbessert", completionLabel: "Text lokal verbessert · Apple Foundation Models")
        }

        let outcome = try await stage.run("Hallo Welt")

        XCTAssertEqual(
            outcome,
            .rewritten(text: "Verbessert", completionLabel: "Text lokal verbessert · Apple Foundation Models")
        )
    }

    // MARK: - Errors

    func testRewriteErrorPropagates() async {
        let stage = RewriteStage { _ in throw StageTestError.boom }

        do {
            _ = try await stage.run("Hallo Welt")
            XCTFail("expected the rewrite error to propagate")
        } catch {
            XCTAssertEqual(error as? StageTestError, .boom)
        }
    }
}

private enum StageTestError: Error, Equatable {
    case boom
}
