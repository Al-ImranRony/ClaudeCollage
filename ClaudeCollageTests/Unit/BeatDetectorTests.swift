//
//  BeatDetectorTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 6c — the onset/beat detector behind auto-beat-sync.
//
//  The DSP is split so the algorithm is pure and headlessly testable: a click track
//  is just an array of PCM samples with impulses at known times, and the detector
//  must recover those times. A second test drives the same detector through an
//  actual generated audio file to prove the AVAssetReader path decodes and downmixes
//  correctly.
//

import XCTest
import AVFoundation
@testable import ClaudeCollage

final class BeatDetectorTests: XCTestCase {

    private var scratch: [URL] = []
    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    // MARK: - Pure sample-based detection

    /// A mono click track: `impulses` at the given seconds over `seconds`, each a
    /// short full-amplitude burst on a silent bed.
    private func clickSamples(sampleRate: Double, seconds: Double, impulses: [Double]) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        let burst = Int(0.01 * sampleRate)   // 10 ms
        for time in impulses {
            let start = Int(time * sampleRate)
            for i in start ..< min(start + burst, samples.count) {
                // Decaying tone so there's real spectral energy, not a lone spike.
                let phase = Double(i - start) / sampleRate
                samples[i] = Float(0.9 * sin(2 * .pi * 880 * phase))
            }
        }
        return samples
    }

    func testDetectsEvenlySpacedClicks() {
        let rate = 22_050.0
        let expected = [0.5, 1.0, 1.5, 2.0, 2.5]
        let samples = clickSamples(sampleRate: rate, seconds: 3, impulses: expected)

        let onsets = BeatDetector.onsets(fromMonoSamples: samples, sampleRate: rate)

        XCTAssertEqual(onsets.count, expected.count, "one onset per click — no doubles, no misses")
        for (detected, target) in zip(onsets, expected) {
            XCTAssertEqual(detected, target, accuracy: 0.06, "onset lands on the click")
        }
    }

    func testSilenceProducesNoOnsets() {
        let samples = [Float](repeating: 0, count: 22_050)
        XCTAssertTrue(BeatDetector.onsets(fromMonoSamples: samples, sampleRate: 22_050).isEmpty)
    }

    func testMinimumInterOnsetSuppressesDoubleTriggers() {
        let rate = 22_050.0
        // Two clicks only 30 ms apart — closer than the 150 ms floor, so the second
        // must be swallowed.
        let samples = clickSamples(sampleRate: rate, seconds: 1, impulses: [0.3, 0.33])
        let onsets = BeatDetector.onsets(fromMonoSamples: samples, sampleRate: rate)
        XCTAssertEqual(onsets.count, 1, "clicks within the refractory window collapse to one")
    }

    // MARK: - Detection through a real audio file

    func testDetectsOnsetsFromAGeneratedAudioFile() async throws {
        let url = try await makeClickAudioFile(seconds: 3, impulses: [0.5, 1.0, 1.5, 2.0, 2.5])
        let onsets = try await BeatDetector().detectOnsets(in: AVURLAsset(url: url))
        // AAC encoding + decoding smears the transients, so allow a looser tolerance
        // and count rather than pin each time.
        XCTAssertGreaterThanOrEqual(onsets.count, 4, "recovers most clicks from the decoded file")
        XCTAssertLessThanOrEqual(onsets.count, 6, "without spurious extra onsets")
    }

    // MARK: - Fixture

    private func makeClickAudioFile(seconds: Double, impulses: [Double]) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Click-\(UUID().uuidString).m4a")
        scratch.append(url)
        let sampleRate = 44_100.0
        let writer = try AVAssetWriter(url: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate, AVEncoderBitRateKey: 96_000])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "fixture", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let total = Int(seconds * sampleRate)
        let burst = Int(0.01 * sampleRate)
        var pcm = [Int16](repeating: 0, count: total)
        for time in impulses {
            let start = Int(time * sampleRate)
            for i in start ..< min(start + burst, total) {
                let phase = Double(i - start) / sampleRate
                pcm[i] = Int16(0.9 * Double(Int16.max) * sin(2 * .pi * 880 * phase))
            }
        }
        let chunk = 1024
        var written = 0
        while written < total {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            let n = min(chunk, total - written)
            if let sb = Self.pcmBuffer(Array(pcm[written ..< written + n]), sampleRate: sampleRate,
                                       pts: CMTime(value: Int64(written), timescale: Int32(sampleRate))) {
                input.append(sb)
            }
            written += n
        }
        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return url
    }

    private static func pcmBuffer(_ samples: [Int16], sampleRate: Double, pts: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                             layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let dataSize = samples.count * 2
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: dataSize, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: dataSize,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        _ = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: dataSize)
        }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sizeArr = [2]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: format, sampleCount: samples.count,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sizeArr,
                                        sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
