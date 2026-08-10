import AIKeyboardShared
import CoreMedia
import CoreVideo
import ReplayKit
import os

// MARK: - Heartbeat, delivery and read

extension SampleHandler {

    // MARK: - Heartbeat

    /// 1 Hz, on its own queue, and it writes `heartbeatAt` and nothing else.
    ///
    /// Separate from frame delivery because they are separate failures: a wedged
    /// handler keeps the process alive while frames stop, and a keyboard that
    /// could not tell those apart would show a live-looking strip over a dead
    /// pipeline. `CaptureFreshness` conditions 1 and 2 are the two halves.
    func startHeartbeat() {
        stopHeartbeat()
        guard let channel else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(200))
        timer.setEventHandler { channel.heartbeat() }
        timer.resume()
        heartbeat = timer
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Delivery

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            // The pool drains anything CoreMedia autoreleased before the callback
            // returns, so a sample cannot sit in the process's pool waiting for a
            // runloop turn that a delivery queue never takes.
            autoreleasepool { sampleVideo(sampleBuffer) }
        case .audioApp, .audioMic:
            // Dropped on purpose rather than fallen through: audio arrives far
            // more often than video and this extension reads neither.
            return
        @unknown default:
            return
        }
    }

    private func sampleVideo(_ sampleBuffer: CMSampleBuffer) {
        framesDelivered &+= 1

        let now = clock.now
        if let last = lastSampledAt, now - last < Self.sampleInterval {
            // Not sampled, but delivery is alive and the keyboard's second
            // liveness condition is watching for exactly that.
            channel?.recordDelivery()
            return
        }
        lastSampledAt = now
        framesSampled &+= 1

        // One `task_info` call per sampled frame — 4 Hz, no allocation — and the
        // shared page is written only when the answer flips, so the status screen
        // reflects the refusal without a seqlock transaction four times a second.
        let footprint = memory.observe()
        channel?.recordFootprint(baselineMB: nil, currentMB: footprint.footprintMB)
        if footprint.changed {
            channel?.setDegraded(footprint.isRefusing)
            Self.log.notice(
                """
                memory degraded=\(footprint.isRefusing, privacy: .public) \
                footprintMB=\(footprint.footprintMB.map { String(format: "%.1f", $0) } ?? "unmeasurable", privacy: .public)
                """
            )
        }

        // Orientation rides as an attachment, not as a property of the image, and
        // a landscape frame read as portrait is read sideways.
        let orientation = Self.orientation(of: sampleBuffer)
        if orientation != lastOrientation {
            lastOrientation = orientation
            // `CGImagePropertyOrientation` is 1...8, so a byte holds it. Clamped
            // rather than truncated so a value outside that range arrives as 255
            // — visibly wrong — instead of wrapping into a different, plausible
            // orientation.
            channel?.recordOrientation(
                Self.band(for: orientation), raw: UInt8(clamping: orientation?.rawValue ?? 0))
            Self.log.notice(
                "video orientation=\(Self.name(of: orientation), privacy: .public)"
            )
        }

        if !hasLoggedFormat, let format = sampleBuffer.formatDescription {
            hasLoggedFormat = true
            let size = CMVideoFormatDescriptionGetDimensions(format)
            let subType = CMFormatDescriptionGetMediaSubType(format)
            channel?.recordFrameFormat(
                width: Int(size.width), height: Int(size.height), pixelFormat: subType)
            Self.log.notice(
                """
                video first-frame \(size.width, privacy: .public)x\
                \(size.height, privacy: .public) format=\
                \(Self.fourCharCode(subType), privacy: .public)
                """
            )
        }

        // One clock reading for the identity and for anything read off this
        // frame, so the record's `capturedAt` is the same instant the page
        // publishes as `currentFrameSampledAt` rather than a few microseconds
        // after it.
        let sampledAt = CaptureClock.now()
        // One page load for both halves of this frame. The crop it carries is
        // our own keyboard's region, which the fingerprint must leave out: our
        // panel repaints its shimmer at 60 Hz for the whole five seconds of a
        // read, and inside the band that moved the identity on every sample and
        // made the freshness gate refuse the reading the tap had just paid for.
        let intent = channel?.intent()
        let fingerprint = Self.fingerprint(
            of: sampleBuffer,
            orientation: Self.band(for: orientation),
            bottomCrop: intent?.frameBottomCrop ?? FrameReduction.Band.bottom)
        if let fingerprint {
            channel?.recordFrame(fingerprint, now: sampledAt)
            serveReadRequest(
                sampleBuffer, intent: intent, identity: fingerprint.identity, sampledAt: sampledAt)
        } else {
            // A frame we could not fingerprint is a frame the freshness gate
            // must not treat as evidence, so delivery is recorded and the
            // identity is left alone rather than being cleared or guessed. It is
            // also not a frame to read: a reading whose identity nothing can
            // confirm could never be shown.
            channel?.count(\.fingerprintFailures)
            channel?.recordDelivery(now: sampledAt)
        }

        if framesSampled % Self.logEvery == 0 {
            Self.log.notice(
                """
                video progress delivered=\(self.framesDelivered, privacy: .public) \
                sampled=\(self.framesSampled, privacy: .public) \
                fingerprinted=\(fingerprint != nil, privacy: .public)
                """
            )
        }
    }

    // MARK: - The read

    /// Answers a raised request with this frame, if there is one to answer.
    ///
    /// Everything here is bounded work on the delivery queue: a page load, a
    /// downscale into a buffer that already exists, and a JPEG encode. The
    /// five-second part is the call `ScreenReadService.start` schedules on its
    /// own queue, and this returns without it.
    ///
    /// **The encode has never been measured on this path.** The "under 0.2 MB
    /// above process base" figure this comment used to quote came from a bare
    /// CLI process in the iOS Simulator encoding a PNG, which the design records
    /// as a floor rather than a measurement. The shipping path is a vImage ARGB
    /// buffer into `CGImageDestination`, inside a broadcast extension, on a
    /// device — three differences, any of which could matter against a ~50 MB
    /// cap. `MemoryGovernor` is what stands between this and jetsam until R2 and
    /// R7 are measured on hardware.
    func serveReadRequest(
        _ sampleBuffer: CMSampleBuffer, intent: CaptureIntent?, identity: FrameIdentity,
        sampledAt: UInt64
    ) {
        // Read once, under the lock, and work with that reference for the rest
        // of this frame. Re-reading per use would let a `broadcastStarted` land
        // between the claim and the answer, so a ticket taken from one session's
        // service could be failed against another's.
        guard let channel, let reads = reads.withLock({ $0 }),
            let ticket = reads.claim(
                intent: intent, identity: identity, capturedAt: sampledAt)
        else { return }

        // The memory refusal is taken *after* the ticket, not before it. Refusing
        // earlier would leave `intent.readNow` unclaimed, so the next frame would
        // try again and the one after that, and the keyboard — which is already
        // waiting on that sequence — would sit through its full twelve seconds and
        // then be told nothing answered. A claimed request is always answered,
        // here with the reason.
        guard !memory.isRefusing else {
            channel.count(\.refusedMemory)
            reads.fail(
                ticket,
                detail: "Screen context is low on memory and did not read the screen.")
            Self.log.error(
                "read refused: footprint is above the watermark, request=\(ticket.sequence, privacy: .public)"
            )
            return
        }

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let jpeg = scaler.jpeg(from: buffer)
        else {
            // The request is answered rather than dropped. The keyboard is
            // already waiting on this sequence, and twelve seconds of silence is
            // the one outcome this pipeline is not allowed to produce.
            reads.fail(ticket, detail: "The screen could not be prepared for reading.")
            Self.log.error("read gave up: the frame could not be downscaled or encoded")
            return
        }

        reads.start(ticket, jpeg: jpeg)
    }
}
