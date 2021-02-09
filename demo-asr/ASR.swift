//
//  ASR.swift
//  Readability
//
//  Created by Durgesh Waghmare  on 30/09/2020.
//  Copyright © 2020 Linnify. All rights reserved.
//

import Foundation
import AVFoundation

public protocol ASRDelegate: class {
    
    func asr(_ asr: ASR, didHypothesizePartialResult partialResult: String)
    func asr(_ asr: ASR, didHypothesizeFinalResult result: String)
    func asrWillRestart(_ asr: ASR)
}

public class ASR {
    
    public struct WordResult: Decodable {
        let confidence: Double?
        let start: TimeInterval?
        let end: TimeInterval?
        let text: String
        
        private enum CodingKeys: String, CodingKey {
            case confidence = "conf"
            case start = "start"
            case end = "end"
            case text = "word"
        }
    }
    
    public enum State {
        case idle
        case recognizing
    }
    
    public typealias Result = [WordResult]
    
    public weak var delegate: ASRDelegate? = nil
    private(set) var targetQueue: DispatchQueue
    private(set) var state: State = .idle
    
    private struct ASRResult: Decodable {
        let result: Result?
        let text: String
    }
    
    private struct ASRPartialResult: Decodable {
        let partial: String
    }
    
    private let asr: OpaquePointer
    private var asrRecognizer: OpaquePointer
    private var grammar: String? = nil
    
    private let workingQueue = DispatchQueue(label: "com.ernie.speech.SpeechRecognitionDemo", qos: .userInitiated)
    
    struct ModelPathNotFoundError: Error {}
    let modelLoaded = true
    
    init(targetQueue: DispatchQueue = .main) throws {
        guard let resourcePath = Bundle.main.resourcePath else { throw ModelPathNotFoundError() }
        let modelPath = resourcePath + "/model_en"
        self.asr = durgesh_ai_model_new(modelPath)
        self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
        self.targetQueue = targetQueue
        
    }
    
//    func loadModel(with modelPath: String){
//        guard let resourcePath = Bundle.main.resourcePath else { throw ModelPathNotFoundError() }
//        let modelPath = resourcePath + "/model_en"
//        self.asr = durgesh_ai_model_new(modelPath)
//    }
    
    func startRecognizing() {
        guard self.state != .recognizing else { return }
        self.state = .recognizing
    }
    
    func stopRecognizing() {
        guard self.state == .recognizing else { return }
        self.state = .idle
        
        let rawResult = String(cString: durgesh_ai_recognizer_final_result(self.asrRecognizer)).data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let internalResult = try decoder.decode(ASRResult.self, from: rawResult)
            
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.asr(self, didHypothesizeFinalResult: internalResult.text)
            }
        } catch {
            print("We somehow have problems with the json: \(error)")
        }
    }
    
    func prepare(with sentences: [String]) {
        print("prepare called")
        let flattenedString = sentences.joined(separator: " ")
//        print("starting recognizer with grammer : \n")
//        print(flattenedString)
        
//        self.asrRecognizer = durgesh_ai_recognizer_new_grm(self.asr, 16000.0, flattenedString.cString(using: .utf8)!)
        
        self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
        self.grammar = flattenedString
    }

    
    func processAudioBufferNew(_ audioBuffer: AVAudioPCMBuffer) {
        guard self.state == .recognizing else {
            print("You must call start recognizing before providing audio data to the recognizer, otherwise results are discarded.")
            return
        }
        
        let isFinalInt = durgesh_ai_recognizer_accept_waveform_s(self.asrRecognizer,
                                                                 audioBuffer.int16ChannelData?[0],
                                                           Int32(audioBuffer.frameLength))
        
        let rawResult = String(cString: durgesh_ai_recognizer_partial_result(self.asrRecognizer)).data(using: .utf8)!
        let decoder = JSONDecoder()

        do {
            let internalResult = try decoder.decode(ASRPartialResult.self, from: rawResult)

            // delegate call
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.asr(self, didHypothesizePartialResult: internalResult.partial)
                print(internalResult.partial)
            }
        } catch {
            print("Somehow we have a bad json: \(error)")
        }

//        let isFinal = isFinalInt != 0
        
//        print("processAudioBuffer called");
//        if isFinal {
//            if let grammar = self.grammar {
////                self.asrRecognizer = durgesh_ai_recognizer_new_grm(self.asr, 16000.0, grammar)
//                self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
//            } else {
//                self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
//            }
//        }
        
    }
    
    func processAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        guard self.state == .recognizing else {
            print("You must call start recognizing before providing audio data to the recognizer, otherwise results are discarded.")
            return
        }
        
        let sourceFormat = audioBuffer.format
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: false)!

        let formatConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)!

//        let frameCapacity = AVAudioFrameCount(targetFormat.sampleRate) * audioBuffer.frameLength / AVAudioFrameCount(audioBuffer.format.sampleRate)
        let frameCapacity = audioBuffer.frameLength

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
        targetBuffer.frameLength = targetBuffer.frameCapacity

        var error: NSError? = nil
        formatConverter.convert(to: targetBuffer, error: &error) { (inPacketCount, outStatus) -> AVAudioBuffer? in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            return audioBuffer
        }

        if let error = error {
            print("Could not convert for ASR: \(error)")
            return
        }
        
        let isFinalInt = durgesh_ai_recognizer_accept_waveform_s(self.asrRecognizer,
                                                           targetBuffer.int16ChannelData?.pointee,
                                                           Int32(targetBuffer.frameLength))
        
        let rawResult = String(cString: durgesh_ai_recognizer_partial_result(self.asrRecognizer)).data(using: .utf8)!
        let decoder = JSONDecoder()

        do {
            let internalResult = try decoder.decode(ASRPartialResult.self, from: rawResult)

            // delegate call
            self.targetQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.asr(self, didHypothesizePartialResult: internalResult.partial)
                print(internalResult.partial)
            }
        } catch {
            print("Somehow we have a bad json: \(error)")
        }

//        let isFinal = isFinalInt != 0
        
//        print("processAudioBuffer called");
//        if isFinal {
//            if let grammar = self.grammar {
////                self.asrRecognizer = durgesh_ai_recognizer_new_grm(self.asr, 16000.0, grammar)
//                self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
//            } else {
//                self.asrRecognizer = durgesh_ai_recognizer_new(self.asr, 16000.0)
//            }
//        }
        
    }
    
//    private func startPartialResultsTimer() {
//        self.stopPartialResultsTimer()
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            self.partialResultsTimer = Timer.scheduledTimer(withTimeInterval: self.partialResultTimeInterval, repeats: true) { [weak self] (timer) in
//                guard let self = self else { return }
//                self.workingQueue.async {
//
//                }
//            }
//        }
//    }
//
//    private func stopPartialResultsTimer() {
//        DispatchQueue.main.async { [weak self] in
//            self?.partialResultsTimer?.invalidate()
//            self?.partialResultsTimer = nil
//        }
//    }
}
