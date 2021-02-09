//
//  SpeechToTextService.swift
//  Readability
//
//  Created by Durgesh Waghmare 29/06/2020.
//  Copyright © 2020 durgesh.ai. All rights reserved.
//

import Foundation
import Speech

enum SpeechToTextServiceError: Error {
    case speechToTextServiceNotPrepared
    case speechRecognizerNotAvailable
    case unknownError
}

protocol SpeechToTextServiceDelegate: class {
    
    func speechToTextServiceDidDetectSpeech(_ service: SpeechToTextService)
    func speechToTextService(_ service: SpeechToTextService, receivedNewText text: String)
    func speechToTextServiceFinished(_ service: SpeechToTextService)
    func speechToTextService(_ service: SpeechToTextService, encounteredError error: Error)
    func speechToTextService(_ service: SpeechToTextService, didChangeState state: SpeechToTextService.State)
    func speechToTextServicWillRestart(_ service: SpeechToTextService)
}

class SpeechToTextService: NSObject {
    
    public let localeIdentifier: String
    
    public weak var delegate: SpeechToTextServiceDelegate? = nil
    
    public enum State {
        case stopped
        case prepared
        case recognizing
    }
    
    public var isAvailable: Bool = false
    
    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.speechToTextService(self, didChangeState: self.state)
            }
        }
    }
    
    private let asr: ASR
    
    public class func requestRecordPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission(completion)
    }
    
    public class func requestSpeechRecognitionAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> ()) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }
    
    private struct SpeechRecognitionSession {
        let audioEngine: AVAudioEngine
//        let speechRecognitionTask: SFSpeechRecognitionTask
//        let speechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest
    }
    
    private var currentSpeechRecognitionSession: SpeechRecognitionSession? = nil
    
    private let workingQueue = DispatchQueue(label: "com.ernie.speech.SpeechRecognitionDemo",
                                             qos: .userInitiated,
                                             attributes: .concurrent,
                                             autoreleaseFrequency: .workItem,
                                             target: nil)
    private let targetQueue: DispatchQueue
    
    init(localeIdentifier: String = "en-US", targetQueue: DispatchQueue = .main) {
        self.localeIdentifier = localeIdentifier
        self.targetQueue = targetQueue
        self.asr = try! ASR(targetQueue: self.workingQueue)
        super.init()
        self.asr.delegate = self
    }

    
    private var hasHeadset: Bool {
        let audioSession = AVAudioSession.sharedInstance()
        let route = audioSession.currentRoute
        return route.outputs.contains(where: { $0.portType == .headphones || $0.portType == .bluetoothA2DP })
    }
    
    private var hasBluetoothHeadset: Bool {
        let audioSession = AVAudioSession.sharedInstance()
        guard let inputs = audioSession.availableInputs else { return false }
        return inputs.contains(where: { $0.portType == .bluetoothHFP })
    }
    
    private var isStoppedByClient: Bool = false
    
    public func start() throws {
        guard state == .stopped else { return }
        
        self.workingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.prepare_internal()
                try self.resume_internal()
            } catch {
                self.targetQueue.async {
                    self.delegate?.speechToTextService(self, encounteredError: error)
                }
            }
        }
    }
    
    public func prepare() throws {
        guard state == .stopped else { return }
        self.workingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.prepare_internal()
            } catch {
                self.targetQueue.async {
                    self.delegate?.speechToTextService(self, encounteredError: error)
                }
            }
        }
    }
    
    public func resume() throws {
        guard state == .prepared else {
            if state == .stopped {
                throw SpeechToTextServiceError.speechToTextServiceNotPrepared
            }
            return
        }
        
        self.workingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.prepareAudioSessionIfNeeded()
                try self.resume_internal()
            } catch {
                self.targetQueue.async {
                    self.delegate?.speechToTextService(self, encounteredError: error)
                }
            }
        }
        
    }
    
    public func pause() {
        guard state == .recognizing else { return }
        guard let currentSpeechRecognitionSession = currentSpeechRecognitionSession else { return }
        let audioEngine = currentSpeechRecognitionSession.audioEngine
        audioEngine.pause()
        state = .prepared
    }
    
    public func stop() {
        guard state == .recognizing else { return }
        
        isStoppedByClient = true
        
        guard let currentSpeechRecognitionSession = currentSpeechRecognitionSession else { return }
        let audioEngine = currentSpeechRecognitionSession.audioEngine
//        let speechRecognitionRequest = currentSpeechRecognitionSession.speechRecognitionRequest
//        let speechRecognitionTask = currentSpeechRecognitionSession.speechRecognitionTask
        
        audioEngine.stop()
//        speechRecognitionRequest.endAudio()
//        speechRecognitionTask.finish()
        
        self.asr.stopRecognizing()
        
        cleanupResources()
        
        state = .stopped
    }
    
    public func restart() throws {
        self.stop()
        self.delegate?.speechToTextServicWillRestart(self)
        try self.start()
    }
    
    public func prepare(with sentences: [String]) {
        self.asr.prepare(with: sentences)
    }
}

extension SpeechToTextService {
    
    private func prepare_internal() throws {
        let audioEngine = AVAudioEngine()
        
        try setupAudioSession()
        let bus = 0
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: bus)
        
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.00, channels: 1, interleaved: true)!
        
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

//        inputNode.installTap(onBus: bus, bufferSize: 4096, format: inputFormat) { (audioBuffer, when) in
//            self.asr.processAudioBuffer(audioBuffer)
//        }
        
        inputNode.installTap(onBus: bus, bufferSize: 4096, format: inputFormat) { (buffer, time) -> Void in
            let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = AVAudioConverterInputStatus.haveData
                return buffer
            }
            
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate))!
            
            var error : NSError?
            _ = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
//            self.delegate?.onDataAvailable(buffer: convertedBuffer)
            self.asr.processAudioBufferNew(convertedBuffer)
        }
        
        audioEngine.prepare()
        
        currentSpeechRecognitionSession = SpeechRecognitionSession(audioEngine: audioEngine)
        
        state = .prepared
    }
    
    private func resume_internal() throws {
        guard let currentSpeechRecognitionSession = currentSpeechRecognitionSession else {
            throw SpeechToTextServiceError.speechToTextServiceNotPrepared
        }
        
        isStoppedByClient = false
        
        self.asr.startRecognizing()
        
        let audioEngine = currentSpeechRecognitionSession.audioEngine
        try audioEngine.start()
        state = .recognizing
    }
    
    private func prepareAudioSessionIfNeeded() throws {
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category != .playAndRecord else { return }
        try setupAudioSession()
    }
    
    private func setupAudioSession() throws {
//        let audioSession = AVAudioSession.sharedInstance()
//        try audioSession.setCategory(.playAndRecord, options: .defaultToSpeaker)
//        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        #if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(AVAudioSession.Category.record)
        try? audioSession.setMode(AVAudioSessionModeMeasurement)
        try? audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        #endif
    }
    
    private func cleanupResources() {
        guard let speechRecognitionSession = currentSpeechRecognitionSession else { return }
        let audioEngine = speechRecognitionSession.audioEngine
        removeTap(from: audioEngine, onBus: .zero)
        
        // Release the current session resources
        self.currentSpeechRecognitionSession = nil
    }
    
    private func removeTap(from audioEngine: AVAudioEngine, onBus bus: AVAudioNodeBus) {
        audioEngine.inputNode.removeTap(onBus: bus)
        audioEngine.inputNode.reset()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }
    }
}

extension SpeechToTextService: SFSpeechRecognizerDelegate {
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        self.isAvailable = true
    }
}

extension SpeechToTextService: SFSpeechRecognitionTaskDelegate {
    
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        guard self.state == .recognizing else { return }
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextServiceDidDetectSpeech(self)
        }
    }
    
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextServiceFinished(self)
        }
    }
    
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        //
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        guard successfully else {
            let error = task.error ?? SpeechToTextServiceError.unknownError
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.speechToTextService(self, encounteredError: error)
            }
            return
        }
        
        if !isStoppedByClient {
            // Will restart
            self.cleanupResources()
            do {
                self.targetQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.speechToTextServicWillRestart(self)
                }
                try self.prepare_internal()
                try self.resume_internal()
            } catch {
                self.targetQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.speechToTextService(self, encounteredError: error)
                }
            }
        } else {
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.speechToTextServiceFinished(self)
                
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        guard self.state == .recognizing else { return }
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextService(self, receivedNewText: transcription.formattedString)
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextServiceFinished(self)
        }
    }
}

extension SpeechToTextService: ASRDelegate {
    
    func asr(_ asr: ASR, didHypothesizePartialResult partialResult: String) {
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextService(self, receivedNewText: partialResult)
        }
    }
    
    func asr(_ asr: ASR, didHypothesizeFinalResult result: String) {
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextService(self, receivedNewText: result)
        }
    }
    
    func asrWillRestart(_ asr: ASR) {
        self.targetQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.speechToTextServicWillRestart(self)
        }
    }
}
