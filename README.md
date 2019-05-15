# Example iOS chat app for Teneo

This project is an example iOS chat app for Teneo. The project demonstrates the following concepts:
* Text input using the native iOS Speech Recognizer as well as manual text entry.
* Spoken responses using the native iOS Text to Speech (TTS) capability.
* A Chat type UI, based on [MessageKit](https://github.com/MessageKit/MessageKit).
* Usage of the TIE SDK to interact with the Teneo engine.

## Prerequisites
* You need to know the engine URL of a published bot.
* Grant microphone and Speech Recognition access to enable voice commands on the app

## Installation
* Clone the repository.
* Install the TIE dependency by running `pods install` in the project root folder.
* Open the project in XCode by opening `TieChatDemo.xcworkspace`.
* Point the app at your bot's Teneo engine by setting the following variables in the `ViewController.swift` class:
    * `baseUrl`, the base url of your engine, for example `https://myteam-4fe77f.bots.teneo.ai`
    * `solutionEndpoint`, the path or endpoint of your engine, like `/longberry_baristas_0x383bjp5a8e6tscbjd9x03tvb` **Note: make sure it ends with a slash (/)**


## Project details
### TIE SDK connectivity
This project follows TIE SDK connectivity guidelines which are fully detailed in [tie-api-client-ios](https://github.com/artificialsolutions/tie-api-client-ios) SDK. This dependency in the `Podfile` file enables the app to use the TIE SDK and communicate with Teneo Engine.

The `viewDidLoad` method of the app initializes, among other things, the `TieApiService` and UI elements.

User inputs (texts) are sent to Teneo Engine with the helper method `sendToTIE(String text, HashMap<String, String> params)`.

Additionally, user input received from the Speech Recognizer or the keyboard are posted to the Chat UI, and sent to Teneo Engine with this helper method `consumeUserInput(userInput: String)`.

### Speech Recognition
This project implements Apple's native iOS Speech Recognizer (ASR) with [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer). Behind other helper methods that validate app permissions and other conditions, sits the `startAudioEngineAndNativeASR` method, which performs two main tasks:

- Initialize an `SFSRecognizer` to a specific Language ('en-GB' by default).
- Initialize an audio engine, and feed streaming audio data into an ASR Request for processing.

Tapping the microphone button silences any Text to Speech playback before launching the Speech Recognizer. Transcription results are received at the `didFinishRecognition` delegate method, posted as a message bubbles into the Chat UI and finally sent to the Teneo engine for processing.

### Text to Speech
Text to Speech (TTS) is implemented with Apple's iOS native [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfoundation/avspeechsynthesizer). The object `AVSpeechSynthesizer` within the project is the center of voice synthesis, and is initialized, launched and released throughout the lifecycle. In this project, the method `speakIOS12TTS(_utterance:String)` speaks the bot responses received from Teneo engine out loud.

### Chat UI
The Chat UI and input bar are based on the [MessageKit](https://github.com/MessageKit/MessageKit) framework, but implemented as a self contained class inside this project. You can customize message bubble color, avatar, and sender in that class. 

