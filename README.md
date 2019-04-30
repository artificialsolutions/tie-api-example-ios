# tie-api-example-ios

This sample project shows the capabilities of the TIE SDK, working in conjunction with 3rd party ASR, TTS and UI elements, as the form of a Chat app. These are the 4 combined parts of the app that are described ahead:
   - TIE SDK connectivity.
   - Native iOS ASR implementation and a typical Textbox bar to capture user input. 
   - Native Text to Speech (TTS) capability to speak bot replies out loud.
   - A Chat type UI,that is based on MessageKit, but self-contained.

## Prerequisites
   - You need to know the engine URL of a published bot.
   - Grant Microphone Usage and Speech Recognition to enable voice commands on the app

## Installation
   - Clone the repository.
   - Run ```pods install``` on the project root folder to install the TIE dependency.
   - Set ```baseUrl``` and ```solutionEndpoint``` variables in the ```ChatActivity.java``` class, to point at your solution's address, and run the app.


## Project elements Documentation
### TIE SDK connectivity.
This project follows TIE SDK connectivity guidelines which are fully detailed in [```tie-api-example-ios```](https://github.com/artificialsolutions/tie-api-example-ios) example.
This dependency in the **Podfile** file enables the app to use the TIE SDK and communicate with Teneo Engine.

The ```viewDidLoad``` method of the app initializes, among other things, the ```TieApiService``` and UI elements.

Within this app, a text can be sent to Teneo Engine anytime, with this helper method:

```
sendInputToTiE(String text, HashMap<String, String> params)
```
Also, user input incoming from ASR or the keyboard are posted to the Chat UI, and sent to Teneo Engine with this helper method: 
```consumeUserInput(userInput: String)```



### Speech Recognition (ASR)
This project implements Apple's native iOS ASR with [```SFSpeechRecognizer```](https://developer.apple.com/documentation/speech/sfspeechrecognizer).
Behind other helper methods that validate app permissions and other conditions, sits the ```startAudioEngineAndNativeASR``` method, which does two main tasks:

-Initialize an ```SFSRecognizer``` to a specific Language (```en-GB``` by default).

-Initialize an audio engine, and feed streaming audio data into an ASR Request for processing.

Tapping the microphone button silences any TTS playback before launching ASR. Transcription results are received at the ```didFinishRecognition``` delegate method, posted as a message bubbles into the Chat UI and finally sent to Engine for processing.

### TTS
TTS is implemented with Apple's iOS native [```AVSpeechSynthesizer```](https://developer.apple.com/documentation/avfoundation/avspeechsynthesizer).
The object ```AVSpeechSynthesizer``` within the project is the center of voice synthesis, and is initialized, launched and released throughout the lifecycle.
In this project, the method ```speakIOS12TTS(_ utterance:String)```  speaks out loud the bot responses received from Teneo Engine.

### Chat UI
The Chat UI and input bar are based on the [MessageKit](https://github.com/MessageKit/MessageKit) framework, but implemented as a self contained class inside this project.
You can customize message bubble color, avatar, and sender in that class, if you wish. 
