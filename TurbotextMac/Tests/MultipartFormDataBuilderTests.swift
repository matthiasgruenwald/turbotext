import XCTest
@testable import Turbotext

final class MultipartFormDataBuilderTests: XCTestCase {

    private func bodyString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    func testIncludesFileModelAndResponseFormat() {
        let result = MultipartFormDataBuilder.build(
            boundary: "TESTBOUNDARY",
            audioData: Data("AUDIO".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            model: "whisper-large-v3-turbo",
            responseFormat: "text",
            prompt: nil,
            language: nil
        )
        let body = bodyString(result)

        XCTAssertTrue(body.contains("--TESTBOUNDARY\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n"))
        XCTAssertTrue(body.contains("Content-Type: audio/m4a\r\n\r\nAUDIO\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"response_format\"\r\n\r\ntext\r\n"))
        XCTAssertTrue(body.contains("--TESTBOUNDARY--\r\n"))
    }

    func testOmitsPromptFieldWhenNil() {
        let result = MultipartFormDataBuilder.build(
            boundary: "TESTBOUNDARY",
            audioData: Data("AUDIO".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            model: "model-x",
            responseFormat: "text",
            prompt: nil,
            language: nil
        )
        let body = bodyString(result)

        XCTAssertFalse(body.contains("name=\"prompt\""))
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testIncludesPromptFieldWhenProvided() {
        let result = MultipartFormDataBuilder.build(
            boundary: "TESTBOUNDARY",
            audioData: Data("AUDIO".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            model: "model-x",
            responseFormat: "text",
            prompt: "Eigennamen: Foo, Bar",
            language: nil
        )
        let body = bodyString(result)

        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"prompt\"\r\n\r\nEigennamen: Foo, Bar\r\n"))
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testIncludesLanguageFieldWhenProvided() {
        let result = MultipartFormDataBuilder.build(
            boundary: "TESTBOUNDARY",
            audioData: Data("AUDIO".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            model: "model-x",
            responseFormat: "text",
            prompt: nil,
            language: "de"
        )
        let body = bodyString(result)

        XCTAssertFalse(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nde\r\n"))
    }

    func testIncludesBothPromptAndLanguageWhenProvided() {
        let result = MultipartFormDataBuilder.build(
            boundary: "TESTBOUNDARY",
            audioData: Data("AUDIO".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            model: "model-x",
            responseFormat: "text",
            prompt: "hint",
            language: "de"
        )
        let body = bodyString(result)

        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nhint\r\n"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nde\r\n"))
    }

    func testEndsWithClosingBoundary() {
        let result = MultipartFormDataBuilder.build(
            boundary: "B",
            audioData: Data("x".utf8),
            filename: "a.m4a",
            mimeType: "audio/m4a",
            model: "m",
            responseFormat: "text",
            prompt: nil,
            language: nil
        )
        XCTAssertTrue(bodyString(result).hasSuffix("--B--\r\n"))
    }
}
