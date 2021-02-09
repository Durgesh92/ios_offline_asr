//
//  ViewController.swift
//  demo-asr
//
//  Created by Durgesh Waghmare on 30/09/2020.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var label: UILabel!
    
    var isRecognizing = false
    
    let speechService = SpeechToTextService()
    
    @IBAction func startTapped(_ sender: UIButton!) {
        if self.isRecognizing {
            speechService.stop()
        } else {
            speechService.prepare(with: ["hello how are you", "how are things going", "today was a good day", "i love speaking to my phone"])
            try? speechService.start()
        }
        
        self.isRecognizing = !self.isRecognizing
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        SpeechToTextService.requestRecordPermission { (granted) in
            print("Microphone permission granted: \(granted)")
        }
        
        speechService.delegate = self
    }


}

extension ViewController: SpeechToTextServiceDelegate {
    
    func speechToTextServiceFinished(_ service: SpeechToTextService) {
        //
    }
    
    func speechToTextServicWillRestart(_ service: SpeechToTextService) {
        //
    }
    
    func speechToTextServiceDidDetectSpeech(_ service: SpeechToTextService) {
        //
    }
    
    func speechToTextService(_ service: SpeechToTextService, encounteredError error: Error) {
        //
    }
    
    func speechToTextService(_ service: SpeechToTextService, receivedNewText text: String) {
        self.label.numberOfLines = 10
        self.label.text = text
    }
    
    func speechToTextService(_ service: SpeechToTextService, didChangeState state: SpeechToTextService.State) {
        //
    }
}

