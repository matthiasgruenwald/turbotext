import XCTest
@testable import Turbotext

final class RewriteOutputValidatorTests: XCTestCase {
    private let turbotextPrompt = TextImprovementSettings().systemPrompt
    private let dampfAblassenPrompt = DampfAblassenSettings().systemPrompt
    private let emojiPrompt = """
    Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, \
    aber fuege passende Emojis ein. Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze. \
    Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. \
    Gib NUR den Text mit Emojis zurueck, keine Erklaerungen.
    """

    func testThresholdsAreCentralized() {
        XCTAssertEqual(RewriteOutputValidator.promptEchoMinimumRunLength, 30)
        XCTAssertEqual(RewriteOutputValidator.minimumContentWordLength, 4)
        XCTAssertEqual(RewriteOutputValidator.maximumOutputToInputRatio, 5)
    }

    // MARK: - Repro-Fälle

    /// #175-Repro: das On-Device-Modell gibt den Systemprompt wörtlich zurück.
    func testVerbatimPromptEchoIsRejected() {
        let failure = RewriteOutputValidator.validate(
            input: "ich wollte fragen ob wir das treffen morgen verschieben können",
            output: turbotextPrompt,
            systemPrompt: turbotextPrompt
        )
        XCTAssertEqual(failure, .promptEcho)
    }

    /// #179-Repro: das On-Device-Modell umschreibt den Systemprompt, statt das
    /// Diktat zu bearbeiten — kein Inhaltswort der Eingabe taucht in der Ausgabe auf.
    func testRephrasedEchoIsRejected() {
        let failure = RewriteOutputValidator.validate(
            input: "Ich muss morgen die Klassenarbeit korrigieren und brauche Ruhe",
            output: "Meine Aufgabe ist es, ein gesprochenes Transkript zu überarbeiten: Füllwörter entfernen, Grammatik glätten und ausschließlich das Ergebnis liefern.",
            systemPrompt: turbotextPrompt
        )
        XCTAssertEqual(failure, .noInputReference)
    }

    /// #179-Repro: das On-Device-Modell erfindet zu einem kurzen Diktat einen
    /// viel zu langen Text, der die Eingabe zwar erwähnt, aber ausschmückt.
    func testFabricationIsRejected() {
        let failure = RewriteOutputValidator.validate(
            input: "kurze Pause",
            output: "Die Pause ist ein wichtiger Bestandteil des Schulalltags. Während der Pause können sich alle erholen, etwas trinken und miteinander sprechen. Eine Pause hilft dabei, neue Energie zu sammeln und sich danach wieder besser konzentrieren zu können.",
            systemPrompt: turbotextPrompt
        )
        XCTAssertEqual(failure, .fabrication)
    }

    // MARK: - Schwellwerte

    func testPromptEchoRunLengthBoundary() {
        let input = "äh ok ja so"
        let run29 = String(turbotextPrompt.prefix(RewriteOutputValidator.promptEchoMinimumRunLength - 1))
        XCTAssertNil(RewriteOutputValidator.validate(input: input, output: run29, systemPrompt: turbotextPrompt))

        let run30 = String(turbotextPrompt.prefix(RewriteOutputValidator.promptEchoMinimumRunLength))
        XCTAssertEqual(
            RewriteOutputValidator.validate(input: input, output: run30, systemPrompt: turbotextPrompt),
            .promptEcho
        )
    }

    func testShortSystemPromptCannotEcho() {
        let failure = RewriteOutputValidator.validate(input: "das ist ok", output: "Kurz.", systemPrompt: "Kurz.")
        XCTAssertNil(failure)
    }

    func testContentWordLengthBoundary() {
        XCTAssertNil(RewriteOutputValidator.validate(
            input: "das war so ok",
            output: "Alles klar.",
            systemPrompt: turbotextPrompt
        ))
        XCTAssertEqual(
            RewriteOutputValidator.validate(
                input: "das war eine gute Idee",
                output: "Alles klar.",
                systemPrompt: turbotextPrompt
            ),
            .noInputReference
        )
    }

    func testContentWordMatchingIsCaseInsensitive() {
        let failure = RewriteOutputValidator.validate(
            input: "Ich brauche Ruhe",
            output: "Die ruhe kommt bald.",
            systemPrompt: turbotextPrompt
        )
        XCTAssertNil(failure)
    }

    func testFabricationRatioBoundary() {
        let input = "abcde"
        let exactlyFiveTimes = String(repeating: input, count: RewriteOutputValidator.maximumOutputToInputRatio)
        XCTAssertNil(RewriteOutputValidator.validate(
            input: input, output: exactlyFiveTimes, systemPrompt: turbotextPrompt
        ))
        XCTAssertEqual(
            RewriteOutputValidator.validate(
                input: input, output: exactlyFiveTimes + "x", systemPrompt: turbotextPrompt
            ),
            .fabrication
        )
    }

    // MARK: - Legitime Rewrites (keine False Positives)

    func testLegitimateTurbotextRewriteIsAccepted() {
        let failure = RewriteOutputValidator.validate(
            input: "ähm also ich wollte kurz fragen ob wir das Treffen morgen verschieben können ja genau",
            output: "Ich wollte kurz fragen, ob wir das Treffen morgen verschieben können.",
            systemPrompt: turbotextPrompt
        )
        XCTAssertNil(failure)
    }

    func testLegitimateDampfAblassenRewriteIsAccepted() {
        let failure = RewriteOutputValidator.validate(
            input: "Ich bin so sauer der Lärm nebenan geht schon wieder los ich brauche endlich Ruhe zum Arbeiten",
            output: "Ich brauche dringend Ruhe zum Arbeiten. Der Lärm nebenan macht das unmöglich — bitte sorge dafür, dass es leiser wird.",
            systemPrompt: dampfAblassenPrompt
        )
        XCTAssertNil(failure)
    }

    func testLegitimateEmojiTextRewriteIsAccepted() {
        let failure = RewriteOutputValidator.validate(
            input: "Wir sehen uns morgen im Büro",
            output: "Wir sehen uns morgen im Büro! 👋😊",
            systemPrompt: emojiPrompt
        )
        XCTAssertNil(failure)
    }
}
