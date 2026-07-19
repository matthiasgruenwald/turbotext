import Foundation

/// Version-erased façade over `AppleSpeechTranscriptionService` (macOS 26+ only) so
/// callers below the OS floor — and the resolver/tests — don't need `@available` guards
/// sprinkled through call sites.
enum AppleSpeechAvailability {
    static var status: AppleSpeechAvailabilityStatus {
        get async {
            guard #available(macOS 26, *) else { return .unsupportedOS }
            return await AppleSpeechTranscriptionService.availabilityStatus
        }
    }

    static var isAvailable: Bool {
        get async {
            await status.isAvailable
        }
    }

    static func makeTranscriber(
        partialTranscriptHandler: ((String) -> Void)? = nil
    ) -> SpokenWorkflowPipeline.Transcriber? {
        guard #available(macOS 26, *) else { return nil }
        return AppleSpeechTranscriptionService.makeTranscriber(partialTranscriptHandler: partialTranscriptHandler)
    }
}
