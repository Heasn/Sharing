import AVFoundation
import VideoToolbox

@_cdecl("SharingCoreInit")
func SharingCoreInit(extra: UnsafeRawPointer, cb: @escaping FrameCallback, width: UInt = 640, height: UInt = 480, fps: UInt = 30) -> UnsafeMutableRawPointer? {
    let sharingCore = SharingCore(extra: extra, cb: cb, width: width, height: height, fps: fps)
    if sharingCore != nil {
        // retain add 1
        return Unmanaged.passRetained(sharingCore!).toOpaque()
    }
    return nil
}

@_cdecl("SharingCoreBeginScreenCapture")
func SharingCoreBeginScreenCapture(pointer: UnsafeMutableRawPointer) {
    // dot not retain
    let sharingCore = Unmanaged<SharingCore>.fromOpaque(pointer).takeUnretainedValue()
    sharingCore.beginCaptureScreen()
}

@_cdecl("SharingCoreStopScreenCapture")
func SharingCoreStopScreenCapture(pointer: UnsafeMutableRawPointer) {
    // do not retain
    let sharingCore = Unmanaged<SharingCore>.fromOpaque(pointer).takeUnretainedValue()
    sharingCore.stopCaptureScreen()
}

@_cdecl("SharingCoreDeallocate")
func SharingCoreDeallocate(pointer: UnsafeMutableRawPointer) {
    Unmanaged<SharingCore>.fromOpaque(pointer).release()
}

public typealias FrameCallback = @convention(c) (UnsafeRawPointer, UnsafeRawPointer, Int) -> Void

public class SharingCore: NSObject {

    private var captureSession: AVCaptureSession
    private var outputDelegate: VideoDataOutputSampleBufferDelegate

    public init?(extra: UnsafeRawPointer, cb: @escaping FrameCallback, width: UInt = 640, height: UInt = 480, fps: UInt = 30) {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let screenInput = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
            print("AVCaptureScreenInput use CGMainDisplayID failed")
            return nil
        }
        screenInput.capturesCursor = true
        screenInput.capturesMouseClicks = true
        screenInput.minFrameDuration = CMTimeMake(value: 1, timescale: 60)
        if captureSession.canAddInput(screenInput) {
            captureSession.addInput(screenInput)
        } else {
            print("AVCaptureSession add AVCaptureScreenInput failed")
            return nil
        }

        guard let delegate = VideoDataOutputSampleBufferDelegate(extra: extra, cb: cb, width: width, height: height, fps: fps) else {
            print("VideoDataOutputSampleBufferDelegate failed")
            return nil
        }

        outputDelegate = delegate

        let queue = DispatchQueue(label: "queue.output.video", qos: .userInitiated)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(outputDelegate, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        } else {
            print("AVCaptureSession add AVCaptureVideoDataOutput failed")
            return nil
        }

        captureSession.commitConfiguration()
    }

    public func beginCaptureScreen() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    public func stopCaptureScreen() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    deinit {
        print("deinit")
    }

}

private class VideoDataOutputSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    var session: VTCompressionSession?
    var encodeQueue: DispatchQueue?
    var callbackQueue: DispatchQueue?
    var cb: FrameCallback?
    var extra: UnsafeRawPointer?

    init?(extra: UnsafeRawPointer, cb: @escaping FrameCallback, width: UInt = 640, height: UInt = 480, fps: UInt = 30) {
        super.init()

        self.extra = extra
        self.cb = cb

        encodeQueue = DispatchQueue(label: "queue.video.encode", qos: .userInitiated)
        callbackQueue = DispatchQueue(label: "queue.callback", qos: .userInitiated)

        var status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(width),
                height: Int32(height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: encodeOutput,
                refcon: unsafeBitCast(self, to: UnsafeMutablePointer.self),
                compressionSessionOut: &session)

        if status != noErr {
            print("VTCompressionSessionCreate failed")
            return nil
        }

        if let session = session {

            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_ProfileLevel,
                    value: kVTProfileLevel_H264_Baseline_5_2)

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_ProfileLevel => kVTProfileLevel_HEVC_Main_AutoLevel")
                return nil
            }

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_RealTime => kCFBooleanTrue")
                return nil
            }

            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_RealTime,
                    value: kCFBooleanTrue)

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_RealTime => kCFBooleanTrue")
                return nil
            }

            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_AllowFrameReordering,
                    value: kCFBooleanFalse)

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_AllowFrameReordering => kCFBooleanFalse")
                return nil
            }

            var maxKeyFrameInterval = 120
            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                    value: CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &maxKeyFrameInterval))

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_MaxKeyFrameInterval => \(maxKeyFrameInterval)")
                return nil
            }

            var fpsValue = fps
            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_ExpectedFrameRate,
                    value: CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &fpsValue))

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_ExpectedFrameRate => \(fpsValue)")
                return nil
            }

            var averageBitRate = width * height * 3 * 4
            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_AverageBitRate,
                    value: CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &averageBitRate))

            if status != noErr {
                print("VTSessionSetProperty failed: kVTCompressionPropertyKey_AverageBitRate => \(averageBitRate)")
                return nil
            }

            let dataRateLimits = [width * height * 3 * 4 * 65, 1] as CFArray
            status = VTSessionSetProperty(session,
                    key: kVTCompressionPropertyKey_DataRateLimits,
                    value: dataRateLimits)

            if status != noErr {
                print("VTSessionSetProperty failed(\(status)): kVTCompressionPropertyKey_DataRateLimits => \(dataRateLimits)")
                return nil
            }

            status = VTCompressionSessionPrepareToEncodeFrames(session)
            if status != noErr {
                print("VTCompressionSessionPrepareToEncodeFrames failed")
                return nil
            }
        }
    }

    internal func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !CMSampleBufferDataIsReady(sampleBuffer) {
            print("sampleBuffer is not ready")
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("CMSampleBufferGetImageBuffer failed")
            return
        }

        if let session = session, let queue = encodeQueue {
            queue.async {
                let presentationTimestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                let duration = CMSampleBufferGetOutputDuration(sampleBuffer)
                let status = VTCompressionSessionEncodeFrame(session,
                        imageBuffer: imageBuffer,
                        presentationTimeStamp: presentationTimestamp,
                        duration: duration,
                        frameProperties: nil,
                        sourceFrameRefcon: nil,
                        infoFlagsOut: nil)

                if status != noErr {
                    print("VTCompressionSessionEncodeFrame failed")
                }
            }
        }
    }

    fileprivate func transferHeader(sps: NSData, pps: NSData, vps: NSData? = nil) {
        if let callbackQueue = callbackQueue {
            callbackQueue.async { [self] in
                let packet = NSMutableData()

                if vps != nil {
                    var vpsLengthHeader: Int32 = Int32((vps!.count))
                    packet.append(NSData(bytes: &vpsLengthHeader, length: 4) as Data)
                    packet.append(vps! as Data)
                }

                var spsLengthHeader: Int32 = Int32((sps.count))
                packet.append(NSData(bytes: &spsLengthHeader, length: 4) as Data)
                packet.append(sps as Data)

                var ppsLengthHeader: Int32 = Int32((pps.count))
                packet.append(NSData(bytes: &ppsLengthHeader, length: 4) as Data)
                packet.append(pps as Data)

                cb?(extra!, packet.bytes, packet.count)
            }
        }
    }

    fileprivate func transferBody(data: NSData) {
        if let callbackQueue = callbackQueue {
            callbackQueue.async { [self] in
                let packet = NSMutableData()

                var dataLengthHeader: Int32 = Int32((data.count))
                packet.append(NSData(bytes: &dataLengthHeader, length: 4) as Data)
                packet.append(data as Data)

                cb?(extra!, packet.bytes, packet.count)
            }
        }
    }

    deinit {
        print("delegate deinit")
        if (session != nil) {
            VTCompressionSessionCompleteFrames(session!, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session!);
            session = nil;
        }
    }
}

private func encodeOutput(outputCallbackRefCon: UnsafeMutableRawPointer?,
                          sourceFrameRefCon: UnsafeMutableRawPointer?,
                          status: OSStatus,
                          infoFlags: VTEncodeInfoFlags,
                          sampleBuffer: CMSampleBuffer?) -> Void {

    let caller = unsafeBitCast(outputCallbackRefCon, to: VideoDataOutputSampleBufferDelegate.self)

    guard status == noErr else {
        print("outputCallback: status = \(status)")
        return
    }

    if infoFlags == .frameDropped {
        print("outputCallback: frame dropped")
        return
    }

    guard let sampleBuffer = sampleBuffer else {
        print("outputCallback: sampleBuffer is nil")
        return
    }

    if CMSampleBufferDataIsReady(sampleBuffer) != true {
        print("outputCallback: sampleBuffer data is not ready")
        return
    }

    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
        let rawDic: UnsafeRawPointer = CFArrayGetValueAtIndex(attachments, 0)
        let dic: CFDictionary = Unmanaged.fromOpaque(rawDic).takeUnretainedValue()

        if !CFDictionaryContainsKey(dic, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
            // is key frame

            let format = CMSampleBufferGetFormatDescription(sampleBuffer)
            var spsSize: Int = 0
            var spsCount: Int = 0
            var nalHeaderLength: Int32 = 0
            var sps: UnsafePointer<UInt8>?

            var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                    parameterSetIndex: 0,
                    parameterSetPointerOut: &sps,
                    parameterSetSizeOut: &spsSize,
                    parameterSetCountOut: &spsCount,
                    nalUnitHeaderLengthOut: &nalHeaderLength)
            if status != noErr {
                print("CMVideoFormatDescriptionGetH264ParameterSetAtIndex failed: Index = 0")
                return
            }

            // pps
            var ppsSize: Int = 0
            var ppsCount: Int = 0
            var pps: UnsafePointer<UInt8>?

            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                    parameterSetIndex: 1,
                    parameterSetPointerOut: &pps,
                    parameterSetSizeOut: &ppsSize,
                    parameterSetCountOut: &ppsCount,
                    nalUnitHeaderLengthOut: &nalHeaderLength)
            if status != noErr {
                print("CMVideoFormatDescriptionGetH264ParameterSetAtIndex failed: Index = 1")
                return
            }

            let spsData: NSData = NSData(bytes: sps, length: spsSize)
            let ppsData: NSData = NSData(bytes: pps, length: ppsSize)

            caller.transferHeader(sps: spsData, pps: ppsData)
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr {
            var bufferOffset: Int = 0
            let AVCCHeaderLength = 4

            while bufferOffset < (totalLength - AVCCHeaderLength) {
                var NALUnitLength: UInt32 = 0
                // first four character is NALUnit length
                memcpy(&NALUnitLength, dataPointer?.advanced(by: bufferOffset), AVCCHeaderLength)

                // big endian to host endian. in iOS it's little endian
                NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)

                let data: NSData = NSData(bytes: dataPointer?.advanced(by: bufferOffset + AVCCHeaderLength), length: Int(NALUnitLength))

                caller.transferBody(data: data)

                // move forward to the next NAL Unit
                bufferOffset += Int(AVCCHeaderLength)
                bufferOffset += Int(NALUnitLength)
            }
        }
    }
}