//
//  ViewController.swift
//  HWDetector
//
//  Created by Yuuki Nishiyama on 2019/08/31.
//  Copyright © 2019 Yuuki Nishiyama. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, HotwordDelegate{
    
    func didHotwordDetect() {
        print("The hotword is detected!")
    }
    
    let hwDetector = MyHWDetector()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        hwDetector.delegate = self
        do {
            try hwDetector.startSession()
        }catch{
            print("Error")
        }
    }


}

public protocol HotwordDelegate {
    func didHotwordDetect()
}

public class MyHWDetector: NSObject {
    private var audioEngine = AVAudioEngine()
    
    let RESOURCE = Bundle.main.path(forResource: "common", ofType: "res")
    let MODEL    = Bundle.main.path(forResource: "jarvis", ofType: "pmdl")
    var wrapper:SnowboyWrapper
    
    public var delegate:HotwordDelegate?
    override init() {
        wrapper = SnowboyWrapper(resources: RESOURCE, modelStr: MODEL)
        wrapper.setSensitivity("0.5")
        wrapper.setAudioGain(1.0)
        super.init()
    }
    
    deinit{
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.reset()
    }
    
    public func startSession() throws {
        // Reset the audio engine
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.reset()
        
        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord,
                                     mode: .default,
                                     options: [.allowBluetoothA2DP, .allowAirPlay, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        
        let inputFormat  = inputNode.inputFormat(forBus: 0)
        // let outputFormat = inputNode.outputFormat(forBus: 0)
        
        print("input",  inputFormat)
        
        // <1 ch,  16000 Hz, Float32>
        let hwdFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate:   16000,
                                      channels:     1,
                                      interleaved:  true)!
        
        
        inputNode.installTap(onBus: 0,
                             bufferSize: 16384,
                             format: inputFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                                
                                var convertedBuffer:AVAudioPCMBuffer? = buffer
                                
                                // Convert audio format from 44100Hz to 16000Hz from Hotword Detection
                                // https://medium.com/@prianka.kariat/changing-the-format-of-ios-avaudioengine-mic-input-c183459cab63
                                if buffer.format != hwdFormat {
                                    if let converter = AVAudioConverter(from: inputFormat, to: hwdFormat) {
                                        convertedBuffer = AVAudioPCMBuffer(pcmFormat:  hwdFormat,
                                                                           frameCapacity: AVAudioFrameCount( hwdFormat.sampleRate * 0.4))
                                        let inputBlock : AVAudioConverterInputBlock = { (inNumPackets, outStatus) -> AVAudioBuffer? in
                                            outStatus.pointee = AVAudioConverterInputStatus.haveData
                                            let audioBuffer : AVAudioBuffer = buffer
                                            return audioBuffer
                                        }
                                        var error : NSError?
                                        if let uwConvertedBuffer = convertedBuffer {
                                            converter.convert(to: uwConvertedBuffer, error: &error, withInputFrom: inputBlock)
                                        }
                                    }
                                }
                                
                                if let newbuffer = convertedBuffer{
                                    // Detect the hotword from audio buffer
                                    let array = Array(UnsafeBufferPointer(start: newbuffer.floatChannelData?[0], count:Int(newbuffer.frameLength)))
                                    let result = self.wrapper.runDetection(array, length: Int32(newbuffer.frameLength))
                                    /// 1 = detected, 0 = other voice or noise, -2 = no voice and noise
                                    if result == 1 {
                                        self.delegate?.didHotwordDetect()
                                    }
                                }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    public func stopSession(){
        self.audioEngine.stop()
        self.audioEngine.disconnectNodeOutput(audioEngine.inputNode)
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.reset()
    }
}
