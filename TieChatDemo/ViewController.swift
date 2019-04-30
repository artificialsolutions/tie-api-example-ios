//
//  ViewController.swift
//  TieChatDemo
//
//  Created by Josh Galher on 24/10/2018.
//  Copyright © 2019 ArtificialSolutions. All rights reserved.
//

import UIKit
import TieApiClient
import Speech
import AVFoundation
import Accelerate


class ViewController: MessagesViewController,
    //Native iOS ASR/TTS delegates
    AVSpeechSynthesizerDelegate,
    SFSpeechRecognitionTaskDelegate,
    SFSpeechRecognizerDelegate,
    AVAudioPlayerDelegate
    {
    
    //Initialize variables
    var messages: [Message] = []
    var member: Member!
    var audioPlayer: AVAudioPlayer?
    
    //** STARTUP METHODS
    var timer:Timer
    required init?(coder decoder: NSCoder) {
        timer = Timer()
        super.init(coder: decoder)
    }
    
    
    ///*** iOS Lifecycle methods:***
    override func viewDidLoad() {
        super.viewDidLoad()
        _ = self.audioEngine
        nativeSpeechRecognizer?.delegate=self
        
        //Initialize Chat UI
        member = Member(name: "", color: UIColor(white: 1, alpha: 0))// transparent white invisible chat bubbles
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messageInputBar.delegate = self
        messagesCollectionView.messagesDisplayDelegate = self

        setMicrophoneButtonToClosed(); //Initialize mic button as closed
        
        //Set up TeneoEngine service
        let BASE_URL = "fill_in_base url_before_use";
        let ENDPOINT = "fill_in_endpoint_url_before_use";
        
        //Setup TIE API
        do {
            try? TieApiService.sharedInstance.setup(BASE_URL, endpoint: ENDPOINT)
            print("TeneoEngine Service is SETUP")
        }catch {
            print("ERROR SETUP TeneoEngine service")
        }
        
        //Set up an audio player for beeps, to be used on the mic button
        do {
            self.audioPlayer =  try AVAudioPlayer(contentsOf: NSURL(fileURLWithPath: Bundle.main.path(forResource: "micon", ofType: "aiff")!) as URL)
        } catch {
            print("Error")
        }
        //Set up audio seession features.
        setSessionPlayAndRecord()
        
        // Create Observers for keyboard appearances and disappearances,
        // ...keep the chat window scrolled all the way up in both cases
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        sendToTIE(textForEngine: "")
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        TieApiService.sharedInstance.closeSession({ response in
            print("Teneo iEngine CLOSE SESSION success")
        },  failure: { error in
            print("Teneo iEngine CLOSE SESSION error")
        })
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //Release observers when app leaves foreground
        NotificationCenter.default.removeObserver(self)
    }
    ///// END iOS lifecycle methods
    
    
    
    //***Keyboard listener methods
    @objc func keyboardWillAppear() {
        messagesCollectionView.scrollToBottom(animated: true)
    }
    @objc func keyboardWillDisappear() {
        messagesCollectionView.scrollToBottom(animated: true)
    }
    
    //*** Microphone button methods
    func setMicrophoneButtonToOpened(){
        let micButton = makeButton(named: "ic_mic_red")
        let items = [micButton]
        messageInputBar.setStackViewItems(items, forStack: .right, animated: false)
        micButton.onTouchUpInside { (micButton) in
            self.handleUserVoiceInput()
        }
    }
    
    func setMicrophoneButtonToClosed(){
        let micButton = makeButton(named: "ic_mic")
        let items = [micButton]
        messageInputBar.setStackViewItems(items, forStack: .right, animated: false)
        micButton.onTouchUpInside { (micButton) in
            self.handleUserVoiceInput()
        }
    }

    //Returns input bar button object
    private func makeButton(named: String) -> InputBarButtonItem {
        return InputBarButtonItem()
            .configure {
                $0.spacing = .fixed(0)
                $0.image = UIImage(named: named)
                $0.setSize(CGSize(width: 40, height: 40), animated: true)
                $0.tintColor = UIColor(white: 0.8, alpha: 1)
        }
    }
    
    
    //Post user input to Chat UI and send it to engine
    func consumeUserInput(userInput: String){
        let newMessage = Message(
            member: member,
            text: userInput,
            messageId: UUID().uuidString)
        
        //Post new user input to chat window, clear the text input box.
        messages.append(newMessage)
        self.messageInputBar.inputTextView.text=""
        //Send result to Teneo Engine, and change microphone button UI to "Closed"
        sendToTIE(textForEngine: newMessage.text)
    }
    
    //Send message to Teneo Engine
    func sendToTIE(textForEngine: String){
        let params = [String: String]()
        TieApiService.sharedInstance.sendInput(textForEngine,
                                               parameters: params,
                                               success: { response in
                                                let tieMessage = Message(member: Member(name: " ", color: UIColor(white: 1, alpha: 0)),
                                                    text: response.output.text,
                                                    messageId: "TeneoEngine")
                                                self.speakIOS12TTS(response.output.text)
                                                self.messages.append(tieMessage)
                                                DispatchQueue.main.async{
                                                    self.messagesCollectionView.reloadData()
                                                }
                                                //Hide keyboard, use UI Thread
                                                DispatchQueue.main.async { [unowned self] in
                                                    self.messageInputBar.inputTextView.resignFirstResponder()
                                                }
        }, failure: { error in
            print("TiE sendInput ERROR: "+error.localizedDescription.description)
        })
    }
    
    
    ///*** ASR METHODS
    //Sets a flag that enables the microphone button, prevents crashes that can happen
    var micEnabled:Bool=true
    @objc func enableMicWithDelay(){
        micEnabled=true
    }
    
    func handleUserVoiceInput(){
        //Check wether ASR is allowed, that is, ...if user wants to do voice input, (mic button is visible, keyboard is not visible and unavailable for input)
        if(micEnabled==true){
            stopTTSiOS12()
            // First, Check for Audio Permissions
            AVAudioSession.sharedInstance().requestRecordPermission () {
                [unowned self] allowed in
                if allowed {
                    SFSpeechRecognizer.requestAuthorization { authStatus in
                        OperationQueue.main.addOperation {
                            switch authStatus{
                            case .authorized:
                                print("Speech Recognition Permission: AUTHORIZED")
                                //If permissions are OK, continue launching ASR:
                                self.handleUserVoiceInputPermissionsOK()
                            case .denied:
                                print("Speech Recognition Permission: DENIED")
                            case .restricted:
                                print("Speech Recognition Permission: RESTRICTED")
                            case .notDetermined:
                                print("Speech Recognition Permission: NOT DETERMINED")
                            @unknown default:
                                print("Error: NOT DETERMINED")
                            }
                        }
                    }
                } else {
                    print("User DENIED Recording Permission :(")
                }
            }
        }
    }
    
    
    //Takes input from ASR and sends it to Engine, when necessary system permissions are already approved.
    func handleUserVoiceInputPermissionsOK(){ //at this point Microphone and Speech Recognitions are already granted
        if(micEnabled==true){
            //Stop TTS before starting ASR
            if(ttsIOS.isSpeaking==true){
                stopTTSiOS12()
            }
            //cancels any ongoing ASR
            cancelNativeRecording();
            
            //If no ASR transaction is active, start ASR
            if(isNativeASRBusy==false){
                startAudioEngineAndNativeASR()
            }
            else{
                //If ASR is active, cancel it
                stopNativeRecording()
                print("Stop Recording")
            }
            
            //Disables the microphone right after tapping it, and reenables it after 200 milliseconds.
            //This allow the Audio object lifeycle enough time to free resources, and become available again.
            DispatchQueue.main.async {
                self.timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector:  #selector(ViewController.enableMicWithDelay), userInfo: nil, repeats: false)
                self.micEnabled=false
            }
        }
    }
    
    
    //iOS12 NATIVE ASR TTS for iOS12, is made up of two parts:
    //1) an audio recorder that streams data into a 2) SFSpeechRecognizer.
    //In this implementation, ASR, TTS and UI elements are fine tuned to use audio resources without interfering with each others' task.
    var audioRecorder:AVAudioRecorder!
    let audioEngine = AVAudioEngine()
    var inputNode:AVAudioInputNode!
    var nativeSpeechRecognizer = SFSpeechRecognizer()
    var nativeASRRequest = SFSpeechAudioBufferRecognitionRequest()
    var nativeASRTask : SFSpeechRecognitionTask?
    var isNativeASRBusy=false //a flag that tracks wether an ASR transaction is active
    var startASRAfterTTS=false //a flag that indicates an ASR transaction must be launched after an ongoing TTS transaction is done speaking.
    
    //ASR TTS Timers
    let utteranceTimeoutSeconds:Double=1.0 //Max time of silence allowed between spoken words before the ASR is stopped.
    let firstSpeechTimeoutSeconds:Double=4.0 //Max time without user utterances allowed after the mic is tapped, before ASR is suspended.
    var endOfSpeechTimeoutTimer:Timer! //A timer that triggers after X seconds without a change in the (partial) ASR result.
    var tooFast=false //flag that keeps track, wether the user is tapping the mic button too fast.
    var tooFastTimer:Timer! //A timer that tracks and ignores microphone button taps that happen too often, less than [tooFastConstant] seconds apart.
    let tooFastConstant = 0.3 //time constant of [tooFastTimer]
    //helper methods for tooFast
    func tooFastTrue(){
        tooFast = true
    }
    @objc func tooFastFalse(){
        tooFast = false
    }
    
    @objc func doNativeRecording(){
        if(tooFast == false){
            //ignore fast mic taps during the next 300 mS
            tooFast = true
            //allos mic taps again, after [tooFastConstant] seconds.
            tooFastTimer = Timer.scheduledTimer(timeInterval: tooFastConstant, target: self, selector:  #selector(ViewController.tooFastFalse), userInfo: nil, repeats: false)
            if(isNativeASRBusy==false){
                do{
                    try startNativeRecording() //launch Audio Recorder
                }
                catch{
                    print("ERROR: startNativeRecording() Exception")
                }
            }
            else{
                stopNativeRecording()
            }
        }
        else{
            print("*** IGNORING FAST TAP ***")
        }
    }
    
    func startNativeRecording() throws {
        stopTTSiOS12()
        if(isIOSTTS12speaking==true){
            //Set flag that launches ASR when TTS is done speaking
            startASRAfterTTS=true
        }
        else{
            startAudioEngineAndNativeASR()
        }
    }
    
    //Setup Audio Session playback and recording features
    func setSessionPlayAndRecord() {
        let session:AVAudioSession = AVAudioSession.sharedInstance()
        do{
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        }
        catch let e as NSError{
            print("Could not set session category: "+e.description)
        }
        
        do{
            try session.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
        }
        catch let e as NSError{
            print("Could not set output to speaker: "+e.description)
        }
        
        do{
            try session.setActive(true)
        }
        catch let e as NSError{
            print("Could not make session active"+e.description)
        }
        
    }
    
    
    func startAudioEngineAndNativeASR(){
        //stop any ongoing TTS
        if(isIOSTTS12speaking==true){
            stopTTSiOS12()
        }
        
        //Set up ASR recognizer, ASR request and delegate
        nativeASRRequest = SFSpeechAudioBufferRecognitionRequest()
        nativeSpeechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))!  //Setup SpeechRecognizer for UK English
        nativeASRTask = nativeSpeechRecognizer?.recognitionTask(with: nativeASRRequest, delegate: self)
        nativeSpeechRecognizer?.delegate=self
        
        //Plug the app's audio input node to the microphone input, then specify a format.
        self.inputNode = audioEngine.inputNode
        let recordingFormat = inputNode!.outputFormat(forBus: 0)
        
        //Change microphone UI to open status (red)
        setMicrophoneButtonToOpened()
        isNativeASRBusy=true //Set the ASR flag as busy
        
        //Connect a tap on the microphone input to fetch audio packets, then stream them to the ASR recognizer
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat){(buffer, _) in
            self.nativeASRRequest.append(buffer)
        }
        
        //Start the audio engine, close microphone if an error happens
        do{
            try audioEngine.start()
        }
        catch let error as NSError{
            setMicrophoneButtonToClosed();
            print("ENGINE START EXCEPTION: "+error.description)
        }
        
        //Activate [endOfSpeechTimeoutTimer]. This timer is later if invalidated when user speech is first detected.
        self.endOfSpeechTimeoutTimer = Timer.scheduledTimer(timeInterval: firstSpeechTimeoutSeconds, target: self, selector:  #selector(ViewController.stopNativeRecording), userInfo: nil, repeats: false)
    }
    
    
    func resetEndOfSpeechTimer(){
        print("*** resetEndOfSpeechTimer ***")
        //Invalidate the timer, if the timer is active
        if(!(endOfSpeechTimeoutTimer==nil)){
            self.endOfSpeechTimeoutTimer!.invalidate()
        }
        self.endOfSpeechTimeoutTimer = nil
        
        //Reset the timer to start ticking again
        self.endOfSpeechTimeoutTimer = Timer.scheduledTimer(timeInterval: utteranceTimeoutSeconds, target: self, selector:  #selector(ViewController.stopNativeRecording), userInfo: nil, repeats: false)
    }
    
    
    
    ///*** NATIVE ASR DELEGATE METHODS
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("*NATIVE ASR - speechRecognitionDidDetectSpeech")
    }
    
    //Handle partial ASR hypotheses
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        //Stop any ongoing TTS transaction and reset end of speech utterance timer.
        stopTTSiOS12()
        resetEndOfSpeechTimer()
        print("-NATIVE ASR - PARTIAL Hypothesis: "+transcription.formattedString)
        
        //Display partial ASR transcription in the user text input box.
        self.messageInputBar.inputTextView.text = transcription.formattedString
    }
    
    //Handle final ASR results
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        print("*NATIVE ASR - didFinishRecognition")
        let finalASRresult=recognitionResult.bestTranscription.formattedString
        print("-NATIVE ASR - RESULT: "+finalASRresult)
        
        //Consume ASR result, and change microphone button UI to "Closed"
        if (!(finalASRresult.isEmpty)){
            consumeUserInput(userInput: finalASRresult);
            self.messageInputBar.inputTextView.text=""
            setMicrophoneButtonToClosed()
        }
        
        isNativeASRBusy=false
    }
    
    //Handle end of audio detection, wether speech was detected or not.
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("*NATIVE ASR - speechRecognitionTaskFinishedReadingAudio")
        self.endOfSpeechTimeoutTimer.invalidate() //release ASR timer resources
        self.endOfSpeechTimeoutTimer = nil
        setMicrophoneButtonToClosed()
    }
    
    //Handle ASR interruptions.
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("*NATIVE ASR - speechRecognitionTaskWasCancelled")
        setMicrophoneButtonToClosed()
    }
    
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        isNativeASRBusy=false
        print("*NATIVE ASR - didFinishSuccessfully , succesful="+successfully.description)
        setMicrophoneButtonToClosed()
    }
    
    //Stop ASR, but process any results obtained so far
    @objc func stopNativeRecording(){
        print("stopNativeRecording")
        audioEngine.stop()
        nativeASRRequest.endAudio()
        inputNode?.removeTap(onBus: 0)
        inputNode=nil
        isNativeASRBusy=false
    }
    
    //Cancel ASR, and discard any results obtained so far
    func cancelNativeRecording(){
        print("cancelNativeRecording")
        if(!(nativeASRTask==nil)){
            nativeASRTask!.cancel()
        }
        inputNode?.removeTap(onBus: 0)
        inputNode=nil
    }
    ///^^ END NATIVE ASR delegate methods^^
    
    
    //TTS (Native iOS12 Text-to-Speech) helper methods
    var ttsIOS = AVSpeechSynthesizer()
    var isIOSTTS12speaking=false
    func speakIOS12TTS(_ utterance:String){
        print("doTTS native IOS12: "+utterance)
        
        //display available male/female voice actor names for different accents:
        //print(AVSpeechSynthesisVoice.speechVoices())
        
        ttsIOS = AVSpeechSynthesizer()
        ttsIOS.delegate=self
        if(isIOSTTS12speaking){
            ttsIOS.pauseSpeaking(at: .word)
        }
        let speechUtterance = AVSpeechUtterance(string: utterance)
        ttsIOS.speak(speechUtterance)
    }
    
    func stopTTSiOS12(){
        //Set TTS flag, stop TTS, and restart TTS handle
        isIOSTTS12speaking=false
        print("Interruption, CANCELLING TTS iOS12")
        ttsIOS.stopSpeaking(at: .immediate)
        ttsIOS = AVSpeechSynthesizer()
    }
    
    
    //*** TTS (Text-to-Speech) delegate methods
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("*TTSiOS12 - didStartSpeechUtterance")
        isIOSTTS12speaking=true
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("*TTSiOS12 - didFinishSpeechUtterance")
        isIOSTTS12speaking=false
        
        //Launch pending ASR transaction.
        if(startASRAfterTTS==true){
            startASRAfterTTS=false
            //wait 0.1 seconds to free up hardware resources before launching ASR
            timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector:  #selector(ViewController.doNativeRecording), userInfo: nil, repeats: false)
        }
    }
    //*** TTS (Text-to-Speech) delegate methods
}


//Extend the View Controller with a Data Source and  four Delegate
//methods to support CHAT UI features

// *MessagesDataSource
// *MessagesLayoutDelegate
// *MessagesDisplayDelegate
// *MessageInputBarDelegate

extension ViewController: MessagesDataSource {
    func numberOfSections(
        in messagesCollectionView: MessagesCollectionView) -> Int {
        return messages.count
    }
    
    func currentSender() -> Sender {
        return Sender(id: member.name, displayName: member.name)
    }
    
    func messageForItem(
        at indexPath: IndexPath,
        in messagesCollectionView: MessagesCollectionView) -> MessageType {
        
        return messages[indexPath.section]
    }
    
    func messageTopLabelHeight(
        for message: MessageType,
        at indexPath: IndexPath,
        in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 12
    }
    
    func messageTopLabelAttributedText(
        for message: MessageType,
        at indexPath: IndexPath) -> NSAttributedString? {
        
        return NSAttributedString(
            string: message.sender.displayName,
            attributes: [.font: UIFont.systemFont(ofSize: 12)])
    }
}

extension ViewController: MessagesLayoutDelegate {
    func heightForLocation(message: MessageType,
                           at indexPath: IndexPath,
                           with maxWidth: CGFloat,
                           in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 0 //means we're letting MessageKit calculate cell height
    }
}

extension ViewController: MessagesDisplayDelegate {
    func configureAvatarView(
        _ avatarView: AvatarView,
        for message: MessageType,
        at indexPath: IndexPath,
        in messagesCollectionView: MessagesCollectionView) {
        
        let message = messages[indexPath.section]
        let color = message.member.color
        avatarView.backgroundColor = color
    }
}

//Extend the View Controller with Message Input Bar delegate
extension ViewController: MessageInputBarDelegate {
    func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
    }
    
    //Handle "Send" button events
    func messageInputBar(_ inputBar: MessageInputBar, didPressKeyboardSendButton text: String) {
        
        //If textbox is not empty, post a message bubble on the UI and send the text to Teneo Engine
        if(!text.isEmpty){
            inputBar.inputTextView.text = ""
            consumeUserInput(userInput: text)
            
            //Update chat scrollview and scroll to bottom
            messagesCollectionView.reloadData()
            messagesCollectionView.scrollToBottom(animated: true)
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
	return input.rawValue
}
