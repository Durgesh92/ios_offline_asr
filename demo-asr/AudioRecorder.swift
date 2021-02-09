//
//  AudioRecorder.swift
//  demo-asr
//
//  Created by Durgesh Waghmare on 01/10/20.
//

import Foundation
import AVFoundation

@objc public protocol AudioRecorderDelegate: class {
    func onDataAvailable(buffer: AVAudioPCMBuffer)
}

public class AudioRecorder : NSObject
{
    @objc public weak var delegate: AudioRecorderDelegate?
    @objc public let audioEngine = AVAudioEngine()
    var inputNode: AVAudioNode!
    
    public override init()
    {
        super.init()
    }
    
    @objc public func startRecording()
    {
        #if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(AVAudioSessionCategoryRecord)
            try? audioSession.setMode(AVAudioSessionModeMeasurement)
            try? audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        #endif

        inputNode = audioEngine.inputNode
        
        let bus = 0
        let inputFormat = inputNode.outputFormat(forBus: bus)
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.00, channels: 1, interleaved: true)!
        
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!
        
        inputNode.installTap(onBus: bus, bufferSize: 2048, format: inputFormat) { (buffer, time) -> Void in
            let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = AVAudioConverterInputStatus.haveData
                return buffer
            }
            
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate))!
            
            var error : NSError?
            _ = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
            self.delegate?.onDataAvailable(buffer: convertedBuffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    @objc public func stopRecording()
    {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
