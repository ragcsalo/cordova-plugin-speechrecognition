#import "SpeechRecognition.h"
#import <Cordova/CDV.h>
#import <Speech/Speech.h>

#define DEFAULT_LANGUAGE @"en-US"
#define IOS_LIMIT_INTERVAL 55.0 

@interface SpeechRecognition()
@property (strong, nonatomic) NSString *currentFinalized;
@property (strong, nonatomic) dispatch_queue_t recognitionQueue;
@property (assign, nonatomic) BOOL isRestarting; // Prevent collision
@end

@implementation SpeechRecognition

- (void)pluginInitialize {
    [super pluginInitialize];
    self.recognitionQueue = dispatch_queue_create("com.plugin.speech.recognition", DISPATCH_QUEUE_SERIAL);
}

- (void)isRecognitionAvailable:(CDVInvokedUrlCommand*)command {
    BOOL available = ([SFSpeechRecognizer class] != nil);
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:available] callbackId:command.callbackId];
}

- (void)startListening:(CDVInvokedUrlCommand*)command {
    dispatch_async(self.recognitionQueue, ^{
        self.currentCallbackId = command.callbackId;

        if (!self.accumulatedTranscript) {
            self.accumulatedTranscript = [[NSMutableString alloc] init];
            self.currentFinalized = @"";
            self.isRestarting = NO;
        }
        [self checkPermissionsAndStart:command];
    });
}

- (void)checkPermissionsAndStart:(CDVInvokedUrlCommand*)command {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Missing permission"] callbackId:command.callbackId];
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
        if (!granted) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Microphone denied"] callbackId:command.callbackId];
            return;
        }
        dispatch_async(self.recognitionQueue, ^{
            [self setupAndStartRecognition:command];
        });
    }];
}

- (void)setupAndStartRecognition:(CDVInvokedUrlCommand*)command {
    NSString* language = [command argumentAtIndex:0 withDefault:DEFAULT_LANGUAGE];
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:language];
    
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    self.audioEngine = [[AVAudioEngine alloc] init];
    self.currentFinalized = @""; 

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    // Set category once and keep it active
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeMeasurement options:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];

    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    self.recognitionRequest.shouldReportPartialResults = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.loopTimer invalidate];
        self.loopTimer = [NSTimer scheduledTimerWithTimeInterval:IOS_LIMIT_INTERVAL target:self selector:@selector(handleLoopRestart) userInfo:nil repeats:NO];
    });

    AVAudioInputNode *inputNode = self.audioEngine.inputNode;
    __weak SpeechRecognition *weakSelf = self;

    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        if (result) {
            NSString *rawPartial = result.bestTranscription.formattedString;
            NSString *croppedPartial = rawPartial;

            if (weakSelf.currentFinalized.length > 0 && [rawPartial hasPrefix:weakSelf.currentFinalized]) {
                croppedPartial = [rawPartial substringFromIndex:weakSelf.currentFinalized.length];
                croppedPartial = [croppedPartial stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }

            if (result.isFinal) {
                [weakSelf sendResponseToJs:croppedPartial isFinal:YES];
                [weakSelf.accumulatedTranscript appendString:croppedPartial];
                if (![weakSelf.accumulatedTranscript hasSuffix:@" "]) {
                    [weakSelf.accumulatedTranscript appendString:@" "];
                }
                weakSelf.currentFinalized = rawPartial; 
            } else {
                [weakSelf sendResponseToJs:croppedPartial isFinal:NO];
            }
        }

        if (error && error.code != 301 && !weakSelf.isRestarting) {
            [weakSelf handleLoopRestart];
        }
    }];

    AVAudioFormat *format = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [weakSelf.recognitionRequest appendAudioPCMBuffer:buffer];
    }];

    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:nil];
    self.isRestarting = NO;
}

- (void)sendResponseToJs:(NSString*)text isFinal:(BOOL)finalStatus {
    if (text.length == 0 && !finalStatus) return;

    NSDictionary *response = @{
        @"isFinal": @(finalStatus),
        @"final": finalStatus ? text : @"",
        @"partial": finalStatus ? @"" : text
    };
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.currentCallbackId];
}

- (void)handleLoopRestart {
    if (self.isRestarting) return;
    self.isRestarting = YES;

    dispatch_async(self.recognitionQueue, ^{
        [self cleanupForRestart];
        
        // REDUCED DELAY: 0.1s is the "sweet spot" for most iOS devices to clear the buffer without missing speech
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), self.recognitionQueue, ^{
            if (self.currentCallbackId) {
                CDVInvokedUrlCommand *dummy = [[CDVInvokedUrlCommand alloc] initWithArguments:@[[NSNull null]] callbackId:self.currentCallbackId className:@"SpeechRecognition" methodName:@"startListening"];
                [self setupAndStartRecognition:dummy];
            }
        });
    });
}

- (void)cleanupForRestart {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.loopTimer invalidate];
    });
    if (self.audioEngine) {
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
            [self.audioEngine.inputNode removeTapOnBus:0];
        }
        self.audioEngine = nil;
    }
    [self.recognitionRequest endAudio];
    self.recognitionTask = nil;
    self.recognitionRequest = nil;
    self.speechRecognizer = nil;
}

- (void)stopListening:(CDVInvokedUrlCommand*)command {
    dispatch_async(self.recognitionQueue, ^{
        self.isRestarting = NO;
        [self cleanupForRestart];
        if (command) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:self.accumulatedTranscript] callbackId:command.callbackId];
        }
        self.accumulatedTranscript = nil;
    });
}

- (void)getSupportedLanguages:(CDVInvokedUrlCommand*)command {
    NSSet<NSLocale *> *supportedLocales = [SFSpeechRecognizer supportedLocales];
    NSMutableArray *localesArray = [[NSMutableArray alloc] init];
    for(NSLocale *locale in supportedLocales) {
        [localesArray addObject:[locale localeIdentifier]];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:localesArray] callbackId:command.callbackId];
}

- (void)hasPermission:(CDVInvokedUrlCommand*)command {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO] callbackId:command.callbackId];
        return;
    }
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:granted] callbackId:command.callbackId];
    }];
}

- (void)requestPermission:(CDVInvokedUrlCommand*)command {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
                    CDVPluginResult *res = granted ? [CDVPluginResult resultWithStatus:CDVCommandStatus_OK] : [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Microphone Denied"];
                    [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
                }];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Speech Denied"] callbackId:command.callbackId];
            }
        });
    }];
}

@end
