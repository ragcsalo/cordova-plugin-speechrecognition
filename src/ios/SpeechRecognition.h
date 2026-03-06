#import <Cordova/CDV.h>
#import <Speech/Speech.h>

@interface SpeechRecognition : CDVPlugin

@property (strong, nonatomic) SFSpeechRecognizer *speechRecognizer;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@property (strong, nonatomic) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (strong, nonatomic) SFSpeechRecognitionTask *recognitionTask;

// State management for continuous recognition
@property (strong, nonatomic) NSMutableString *accumulatedTranscript;
@property (strong, nonatomic) NSTimer *loopTimer;
@property (strong, nonatomic) NSTimer *safetyTimeoutTimer;
@property (strong, nonatomic) NSString *currentCallbackId;

- (void)isRecognitionAvailable:(CDVInvokedUrlCommand*)command;
- (void)startListening:(CDVInvokedUrlCommand*)command;
- (void)stopListening:(CDVInvokedUrlCommand*)command;
- (void)getSupportedLanguages:(CDVInvokedUrlCommand*)command;
- (void)hasPermission:(CDVInvokedUrlCommand*)command;
- (void)requestPermission:(CDVInvokedUrlCommand*)command;

@end
