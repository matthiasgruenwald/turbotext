// PROTOTYPE — diagnosis harness for issue #178, not production code.

import Darwin
import Foundation
import Speech

@main
struct AssetStatusMonitor {
    static let locale = Locale(identifier: "de-DE")
    static let catalogPath =
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition/purpose_auto/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition.xml"
    static let assetDirPath =
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition/purpose_auto"

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)

        var durationSeconds: Int? = nil
        if CommandLine.arguments.count == 2, let value = Int(CommandLine.arguments[1]) {
            durationSeconds = value
        }

        let start = Date()
        log("# start pid=\(ProcessInfo.processInfo.processIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("# maximum-reserved-locales=\(AssetInventory.maximumReservedLocales)")
        await logReservedLocales("# initial-reserved-locales")
        await logInstalledLocales("# initial-installed-locales")

        await sample("# initial-sample")

        await reserveAndLog()

        while true {
            try? await Task.sleep(for: .seconds(5))
            await sample()
            if let durationSeconds, Date().timeIntervalSince(start) >= Double(durationSeconds) {
                log("# stop duration-reached")
                break
            }
        }
    }

    static func reserveAndLog() async {
        do {
            let alreadyReserved = try await AssetInventory.reserve(locale: locale)
            log("# event reserve ok already-reserved=\(alreadyReserved)")
        } catch {
            log("# event reserve failed error=\(String(describing: error))")
            await installAndLog()
            do {
                let alreadyReserved = try await AssetInventory.reserve(locale: locale)
                log("# event reserve-retry ok already-reserved=\(alreadyReserved)")
            } catch {
                log("# event reserve-retry failed error=\(String(describing: error))")
            }
        }
        await logReservedLocales("# post-reserve-reserved-locales")
    }

    static func installAndLog() async {
        do {
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                log("# event install skipped request=nil")
                return
            }
            log("# event install started")
            try await request.downloadAndInstall()
            log("# event install finished")
        } catch {
            log("# event install failed error=\(String(describing: error))")
        }
    }

    static func sample(_ prefix: String = "") async {
        let prodStatus = await status(of: DictationTranscriber(locale: locale, preset: .progressiveLongDictation))
        let freqStatus = await status(of: DictationTranscriber(
            locale: locale,
            contentHints: DictationTranscriber.Preset.progressiveLongDictation.contentHints,
            transcriptionOptions: DictationTranscriber.Preset.progressiveLongDictation.transcriptionOptions,
            reportingOptions: DictationTranscriber.Preset.progressiveLongDictation.reportingOptions.union([.frequentFinalization]),
            attributeOptions: DictationTranscriber.Preset.progressiveLongDictation.attributeOptions
        ))
        let longStatus = await status(of: DictationTranscriber(locale: locale, preset: .longDictation))

        let installed = await DictationTranscriber.installedLocales
        let installedDe = installed.contains { $0.identifier.hasPrefix("de") } ? 1 : 0

        let reserved = await AssetInventory.reservedLocales
        let reservedDe = reserved.contains { $0.identifier.hasPrefix("de") } ? 1 : 0

        let line = [
            iso8601(Date()),
            prodStatus,
            freqStatus,
            longStatus,
            "installedDe=\(installedDe)",
            "reservedDe=\(reservedDe)",
            "reservedCount=\(reserved.count)",
            "catalogMtime=\(mtime(catalogPath))",
            "assetDirMtime=\(mtime(assetDirPath))",
        ].joined(separator: ";")
        log(prefix.isEmpty ? line : "\(prefix) \(line)")
    }

    static func status(of transcriber: DictationTranscriber) async -> String {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return "installed"
        case .downloading: return "downloading"
        case .supported: return "supported"
        case .unsupported: return "unsupported"
        @unknown default: return "unknown"
        }
    }

    static func logReservedLocales(_ prefix: String) async {
        let reserved = await AssetInventory.reservedLocales
        log("\(prefix)=\(reserved.map(\.identifier).joined(separator: ","))")
    }

    static func logInstalledLocales(_ prefix: String) async {
        let installed = await DictationTranscriber.installedLocales
        log("\(prefix)=\(installed.map(\.identifier).joined(separator: ","))")
    }

    static func mtime(_ path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date
        else { return "absent" }
        return String(Int(date.timeIntervalSince1970))
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func log(_ line: String) {
        print(line)
    }
}
