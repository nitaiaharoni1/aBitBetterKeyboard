// Measures what Vision costs a *process*, not what it costs a call.
//
// The question this answers is the one that decides the capture architecture:
// can `VNRecognizeTextRequest` run inside an iOS app extension that jetsam kills
// at a fixed physical-footprint ceiling? So the metric is `phys_footprint` from
// `task_info(TASK_VM_INFO)` — the same number jetsam reads — sampled in one
// long-lived process across all 30 bar screens, because an extension is
// long-lived and the cost of the first read is not the cost that kills it.
//
// It reports three numbers per run and they are not interchangeable:
//   base   footprint before any Vision work, after the images are on disk
//   peak   highest footprint observed at any sample point
//   final  footprint after the last image and one drained autoreleasepool
// A design fits only if `peak` fits. `final - base` is what does not come back.
// `ledger-peak` is the kernel's own `ledger_phys_footprint_peak`, which catches
// the transients that sampling between images misses; it is always the larger.
//
// Two controls, and neither of them is the Neural Engine:
//
//   compute   `supportedComputeStageDevices` per request. Measured 2026-08-08,
//             `VNDetectTextRectanglesRequest` and `VNRecognizeTextRequest(.fast)`
//             are **cpu-only on macOS and on the iOS Simulator alike**; only
//             `.accurate` lists ane/gpu. An earlier version of the design doc
//             explained the macOS/Simulator gap by ANE deployment; that
//             explanation is false for the two configurations it was invoked to
//             support, and this line is what falsifies it.
//   ledgers   where TASK_VM_INFO charges the bytes. `graphics` is
//             `ledger_tag_graphics_footprint`, `neural` is
//             `ledger_tag_neural_footprint`, `neural-nf` is
//             `ledger_tag_neural_nofootprint` — memory the Neural Engine holds
//             that is explicitly *not* charged to the footprint jetsam reads.
//             `external` is file-backed resident memory, which is charged to
//             resident and not to footprint. The two deployments differ in these
//             columns, not in the model they run.
//
// The `ane-mapped` line stays because it is a true observation about the two
// deployments. It is no longer treated as an explanation of anything.
//
// Fails rather than skips: a missing image, a failed Vision call or a
// `task_info` that will not answer exits non-zero. A probe that cannot measure
// must not print a number.
//
//   Bar/screen-context/harness/run-memory.sh            # both deployments, all configs
//   ./memory-host ../images accurate 1.0                # one run, one config
//   PASSES=2 ./memory-host ../images accurate 1.0       # 60 calls, to show the climb
//   SAME_IMAGE=1 ./memory-host ../images accurate 1.0   # 30 calls, one distinct image

import CoreGraphics
import CoreML
import Foundation
import ImageIO
import MachO
import Vision

// MARK: - Deployment

/// Which of the three deployments produced the numbers below. Every figure this
/// probe prints is meaningless without it.
let deployment: String = {
    #if targetEnvironment(simulator)
    return "iOS Simulator"
    #elseif os(macOS)
    return "macOS"
    #elseif os(iOS)
    return "iOS device"
    #else
    return "unknown"
    #endif
}()

/// Apple Neural Engine frameworks mapped into this process. Reported as an
/// observation, not as an explanation: see the header. The simulator maps none;
/// macOS maps several; a phone maps several. That is true and, for the detector
/// and for `.fast`, irrelevant — both are cpu-only on every deployment measured.
func aneFrameworks() -> [String] {
    var found: [String] = []
    for index in 0..<_dyld_image_count() {
        guard let raw = _dyld_get_image_name(index) else { continue }
        let path = String(cString: raw)
        let leaf = (path as NSString).lastPathComponent
        if leaf.hasPrefix("ANE") || leaf.contains("NeuralEngine") || leaf.contains("Espresso") {
            found.append(leaf)
        }
    }
    return found.sorted()
}

// MARK: - Footprint and where it is charged

struct VMSnapshot {
    let footprint: Double
    let resident: Double
    let internalBytes: Double
    let external: Double
    let compressed: Double
    let graphics: Double
    let neural: Double
    let neuralNoFootprint: Double
    let ledgerPeak: Double
}

func snapshot() -> VMSnapshot {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        die("task_info(TASK_VM_INFO) failed with \(result); nothing can be measured")
    }
    let mb = 1_048_576.0
    return VMSnapshot(
        footprint: Double(info.phys_footprint) / mb,
        resident: Double(info.resident_size) / mb,
        internalBytes: Double(info.internal) / mb,
        external: Double(info.external) / mb,
        compressed: Double(info.compressed) / mb,
        graphics: Double(info.ledger_tag_graphics_footprint) / mb,
        neural: Double(info.ledger_tag_neural_footprint) / mb,
        neuralNoFootprint: Double(info.ledger_tag_neural_nofootprint) / mb,
        ledgerPeak: Double(info.ledger_phys_footprint_peak) / mb)
}

func footprintMB() -> Double { snapshot().footprint }

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(3)
}

// MARK: - Images

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { die("could not decode \(url.lastPathComponent)") }
    return image
}

func scaled(_ image: CGImage, by factor: Double) -> CGImage {
    guard factor != 1.0 else { return image }
    let width = max(1, Int(Double(image.width) * factor))
    let height = max(1, Int(Double(image.height) * factor))
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
    else { die("could not create a \(width)x\(height) scaling context") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let out = context.makeImage() else { die("scaling to \(width)x\(height) produced nothing") }
    return out
}

// MARK: - Configurations

enum Config: String, CaseIterable {
    case decode  // load and drop the image, no Vision at all: the floor
    case jpeg  // decode + encode
    case rects  // VNDetectTextRectanglesRequest alone
    case fast  // .fast recognition + rectangles
    case accurate  // .accurate recognition + rectangles
    case accurateEN = "accurate-en"  // .accurate, no language correction, pinned en-US
}

/// One reused request per process, exactly as a long-lived extension would hold
/// it. Rebuilding the request per image measures a different thing.
///
/// `.accurate` is the configuration `VisionScreenReader.swift:101-105` ships:
/// `.accurate`, `usesLanguageCorrection = true`, `automaticallyDetectsLanguage
/// = true`. `.accurate-en` is a *stock* `VNRecognizeTextRequest` with neither
/// flag set, which is a cheaper request and a different measurement; quoting it
/// as the product's cost is the mistake an earlier probe made.
final class Runner {
    private let config: Config
    private let rectangles = VNDetectTextRectanglesRequest()
    private let recognize = VNRecognizeTextRequest()

    init(config: Config) {
        self.config = config
        switch config {
        case .decode, .jpeg, .rects:
            break
        case .fast:
            recognize.recognitionLevel = .fast
            recognize.recognitionLanguages = ["en-US"]
            recognize.automaticallyDetectsLanguage = true
        case .accurate:
            recognize.recognitionLevel = .accurate
            recognize.recognitionLanguages = ["en-US"]
            recognize.automaticallyDetectsLanguage = true
        case .accurateEN:
            recognize.recognitionLevel = .accurate
            recognize.recognitionLanguages = ["en-US"]
            recognize.automaticallyDetectsLanguage = false
            recognize.usesLanguageCorrection = false
        }
    }

    /// Which compute devices Vision will consider for each request, asked before
    /// anything runs. This is the control that replaced the Neural Engine story.
    func computeDevices() -> [String] {
        func describe(_ request: VNRequest, _ name: String) -> String {
            do {
                let stages = try request.supportedComputeStageDevices
                let text = stages.map { stage, devices -> String in
                    let labels = devices.map { device -> String in
                        switch device {
                        case .cpu: return "cpu"
                        case .gpu: return "gpu"
                        case .neuralEngine: return "ane"
                        @unknown default: return "other"
                        }
                    }.sorted().joined(separator: ",")
                    return "\(stage.rawValue)=[\(labels)]"
                }.sorted().joined(separator: " ")
                return "\(name) \(text)"
            } catch {
                die("supportedComputeStageDevices for \(name) failed: \(error)")
            }
        }
        switch config {
        case .decode, .jpeg: return []
        case .rects: return [describe(rectangles, "rects")]
        case .fast, .accurate, .accurateEN:
            return [describe(rectangles, "rects"), describe(recognize, config.rawValue)]
        }
    }

    func run(_ image: CGImage) {
        switch config {
        case .decode:
            // Force the lazy PNG backing store to materialise, which every other
            // config also pays. Without this the floor is not the same floor.
            guard
                let context = CGContext(
                    data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
            else { die("no 1x1 context") }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        case .jpeg:
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, "public.jpeg" as CFString, 1, nil)
            else { die("no JPEG encoder") }
            CGImageDestinationAddImage(
                destination, image, [kCGImageDestinationLossyCompressionQuality: 0.70] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { die("JPEG encode failed") }
        case .rects:
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([rectangles]) } catch { die("rectangles: \(error)") }
        case .fast, .accurate, .accurateEN:
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([rectangles, recognize]) } catch { die("recognize: \(error)") }
        }
    }
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 3, let config = Config(rawValue: args[2]) else {
    FileHandle.standardError.write(
        Data(
            "usage: memory <images-dir> <\(Config.allCases.map(\.rawValue).joined(separator: "|"))> [scale]\n"
                .utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: args[1])
let scale = args.count >= 4 ? Double(args[3]) ?? 1.0 : 1.0

let environment = ProcessInfo.processInfo.environment
/// How many times to walk the corpus. `.accurate` does not plateau after one
/// pass, so a single number over 30 images is a point on a curve, not a ceiling.
let passes = max(1, Int(environment["PASSES"] ?? "1") ?? 1)
/// Run the same image every time. The gap between this and a normal run is how
/// much of the growth is per-*distinct*-image state rather than per call.
let sameImage = environment["SAME_IMAGE"] == "1"

let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    .filter { $0.hasSuffix(".png") }.sorted()
guard files.count >= 30 else {
    die("expected the 30 bar images in \(directory.path), found \(files.count)")
}

// Exactly one image is alive at a time, which is the shape of the real
// pipeline and the only way the numbers mean Vision rather than an image cache.
// Holding all 30 decoded frames costs ~190 MB on its own and swamps everything
// this probe is trying to measure.
let runner = Runner(config: config)
let devices = runner.computeDevices()
let start = snapshot()
var peak = start.footprint
var rows: [(String, Double)] = []
var firstSize = ""

for pass in 1...passes {
    for name in files {
        autoreleasepool {
            let source = sameImage ? files[0] : name
            let image = scaled(loadImage(directory.appendingPathComponent(source)), by: scale)
            if firstSize.isEmpty { firstSize = "\(image.width)x\(image.height)" }
            runner.run(image)
        }
        let now = footprintMB()
        peak = max(peak, now)
        rows.append((passes > 1 ? "\(name)#\(pass)" : name, now))
    }
}
let settle = autoreleasepool { snapshot() }
peak = max(peak, settle.footprint)

let ane = aneFrameworks()
print("deployment   \(deployment)")
print("compute      \(devices.isEmpty ? "n/a (no Vision request)" : devices.joined(separator: "  |  "))")
print("ane-mapped   \(ane.isEmpty ? "none" : ane.joined(separator: " "))  (observation, not an explanation)")
print(
    "config       \(config.rawValue)  scale=\(scale)  first-image=\(firstSize)  images=\(files.count)  passes=\(passes)  same-image=\(sameImage)  calls=\(rows.count)"
)
print(String(format: "base         %.1f MB", start.footprint))
print(String(format: "peak         %.1f MB", peak))
print(
    String(
        format: "final        %.1f MB   (delta %+.1f MB)", settle.footprint,
        settle.footprint - start.footprint))
print(
    String(format: "ledger-peak  %.1f MB   (kernel's own, catches intra-call transients)", settle.ledgerPeak))
func breakdown(_ label: String, _ s: VMSnapshot) {
    print(
        String(
            format:
                "%-12s foot %7.1f  resident %7.1f  internal %7.1f  external %7.1f  compressed %6.1f  graphics %6.1f  neural %6.1f  neural-nf %7.1f",
            (label as NSString).utf8String!, s.footprint, s.resident, s.internalBytes, s.external,
            s.compressed, s.graphics, s.neural, s.neuralNoFootprint))
}
breakdown("charged@base", start)
breakdown("charged@end", settle)
for (name, value) in rows { print(String(format: "  %-14s %.1f", (name as NSString).utf8String!, value)) }
