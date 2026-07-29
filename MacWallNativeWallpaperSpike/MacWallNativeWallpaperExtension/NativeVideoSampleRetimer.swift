import CoreMedia

enum NativeVideoSampleRetimer {
    static func loopOffset(assetDuration: CMTime, loopIndex: Int64) -> CMTime {
        guard assetDuration.isNumeric,
              CMTimeCompare(assetDuration, .zero) > 0,
              loopIndex >= 0 else {
            return .invalid
        }
        guard loopIndex > 0 else {
            return .zero
        }
        return CMTimeMultiplyByFloat64(assetDuration, multiplier: Double(loopIndex))
    }

    static func offset(_ timing: CMSampleTimingInfo, by offset: CMTime) -> CMSampleTimingInfo {
        CMSampleTimingInfo(
            duration: timing.duration,
            presentationTimeStamp: CMTimeAdd(timing.presentationTimeStamp, offset),
            decodeTimeStamp: timing.decodeTimeStamp.isValid
                ? CMTimeAdd(timing.decodeTimeStamp, offset)
                : .invalid
        )
    }

    static func retime(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) throws -> CMSampleBuffer {
        guard offset.isNumeric else {
            throw RetimingError.nonnumericOffset
        }
        var entryCount = 0
        try check(
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: 0,
                arrayToFill: nil,
                entriesNeededOut: &entryCount
            )
        )
        guard entryCount > 0 else {
            throw RetimingError.missingTiming
        }

        var timings = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: entryCount
        )
        let readStatus = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &entryCount
            )
        }
        try check(readStatus)
        timings = try timings.map { timing in
            try validate(timing, offset: offset)
            let shifted = self.offset(timing, by: offset)
            try validate(shifted, offset: .zero)
            return shifted
        }

        var result: CMSampleBuffer?
        let createStatus = timings.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: buffer.count,
                sampleTimingArray: buffer.baseAddress!,
                sampleBufferOut: &result
            )
        }
        try check(createStatus)
        guard let result else {
            throw RetimingError.missingResult
        }
        return result
    }

    static func validate(_ timing: CMSampleTimingInfo, offset: CMTime) throws {
        guard offset.isNumeric else {
            throw RetimingError.nonnumericOffset
        }
        guard timing.presentationTimeStamp.isNumeric else {
            throw RetimingError.nonnumericPresentationTime
        }
        if timing.duration.isValid, !timing.duration.isNumeric {
            throw RetimingError.nonnumericDuration
        }
        if timing.decodeTimeStamp.isValid, !timing.decodeTimeStamp.isNumeric {
            throw RetimingError.nonnumericDecodeTime
        }
    }

    enum RetimingError: Error, Equatable {
        case status(OSStatus)
        case missingTiming
        case missingResult
        case nonnumericOffset
        case nonnumericPresentationTime
        case nonnumericDuration
        case nonnumericDecodeTime
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw RetimingError.status(status)
        }
    }
}
