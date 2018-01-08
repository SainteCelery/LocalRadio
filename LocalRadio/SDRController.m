//
//  SDRController.m
//  LocalRadio
//
//  Created by Douglas Ward on 5/29/17.
//  Copyright © 2017 ArkPhone LLC. All rights reserved.
//

#import "SDRController.h"
#import "NSFileManager+DirectoryLocations.h"
#import "AppDelegate.h"
#import "SoxController.h"
#import "UDPStatusListenerController.h"
#import "LocalRadioAppSettings.h"
#import "EZStreamController.h"
#import "TaskPipelineManager.h"
#import "TaskItem.h"

@implementation SDRController

//==================================================================================
//	dealloc
//==================================================================================

- (void)dealloc
{
    //[self.udpSocket close];
    //self.udpSocket = NULL;

    /*
    if (self.currentInfoSocket != NULL)
    {
        [self.currentInfoSocket disconnect];
        self.currentInfoSocket = NULL;
    }
    */
}

//==================================================================================
//	init
//==================================================================================

- (instancetype)init
{
    self = [super init];
    if (self) {
        /*
        self.udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        
        NSError *error = nil;
        
        if (![self.udpSocket bindToPort:0 error:&error])
        {
            NSLog(@"Error binding: %@", error);
            return nil;
        }
        
        NSError * socketReceiveError = NULL;
        [self.udpSocket beginReceiving:&socketReceiveError];
        */

        self.radioTaskPipelineManager = [[TaskPipelineManager alloc] init];

        self.rtlsdrTaskMode = @"stopped";
    }
    return self;
}

//==================================================================================
//	terminateTasks
//==================================================================================

- (void)terminateTasks
{
    [self.radioTaskPipelineManager terminateTasks];
}

//==================================================================================
//	startRtlsdrTasksForFrequency:
//==================================================================================

- (void)startRtlsdrTasksForFrequency:(NSDictionary *)frequencyDictionary
{
    //NSLog(@"startRtlsdrTaskForFrequency:category");
    
    CGFloat delay = 0.0;
    
    //[self stopRtlsdrTask];

    if (self.radioTaskPipelineManager.taskPipelineStatus == kTaskPipelineStatusRunning)
    {
        [self.radioTaskPipelineManager terminateTasks];
        
        //delay = 1.0;    // one second
        delay = 0.2;
    }

    self.rtlsdrTaskMode = @"frequency";
    
    int64_t dispatchDelay = (int64_t)(delay * NSEC_PER_SEC);
    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, dispatchDelay);

    //dispatch_after(dispatchTime, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{

        NSArray * frequenciesArray = [NSArray arrayWithObject:frequencyDictionary];
        
        [self dispatchedStartRtlsdrTasksForFrequencies:frequenciesArray category:NULL];
    });
}

//==================================================================================
//	startRtlsdrTasksForFrequencies:category:
//==================================================================================

- (void)startRtlsdrTasksForFrequencies:(NSArray *)frequenciesArray category:(NSMutableDictionary *)categoryDictionary
{
    //NSLog(@"startRtlsdrTaskForFrequencies:category");

    CGFloat delay = 0.0;
    
    if (self.radioTaskPipelineManager.taskPipelineStatus == kTaskPipelineStatusRunning)
    {
        [self.radioTaskPipelineManager terminateTasks];
        
        //delay = 1.0;    // one second
        delay = 0.2;    // one second
    }

    self.rtlsdrTaskMode = @"scan";
    self.rtlsdrCategoryDictionary = categoryDictionary;

    int64_t dispatchDelay = (int64_t)(delay * NSEC_PER_SEC);
    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, dispatchDelay);
    
    //dispatch_after(dispatchTime, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
        [self dispatchedStartRtlsdrTasksForFrequencies:frequenciesArray category:categoryDictionary];
    });
}

//==================================================================================
//	dispatchedStartRtlsdrTasksForFrequencies:category:
//==================================================================================

- (void)dispatchedStartRtlsdrTasksForFrequencies:(NSArray *)frequenciesArray category:(NSDictionary *)categoryDictionary
{
    // values common to both Favorites and Categories
    NSString * nameString = @"";
    NSNumber * categoryScanningEnabledNumber = [NSNumber numberWithInteger:0];
    NSMutableString * frequencyString = [NSMutableString stringWithFormat:@"-f 89100000"];  // can be single frequency, multiple frequencies or range
    NSNumber * samplingModeNumber = [NSNumber numberWithInteger:0];
    NSNumber * tunerGainNumber = [NSNumber numberWithFloat:49.5f];
    NSNumber * tunerAGCNumber = [NSNumber numberWithInteger:0];
    NSNumber * tunerSampleRateNumber = [NSNumber numberWithInteger:10000];
    NSNumber * oversamplingNumber = [NSNumber numberWithInteger:4];
    NSString * modulationString = @"fm";
    NSNumber * squelchLevelNumber = [NSNumber numberWithInteger:0];
    NSNumber * squelchDelayNumber = [NSNumber numberWithInteger:0];
    NSString * optionsString = @"";
    NSNumber * firSizeNumber = [NSNumber numberWithInteger:9];
    NSString * atanMathString = @"std";
    NSString * audioOutputFilterString = @"";
    NSString * audioOutputString = @"";
    NSString * streamSourceString = @"";

    NSNumber * statusPortNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"StatusPort"];
    
    NSString * statusFunctionString = @"No active tuning";
    
    BOOL enableDirectSamplingQBranchMode = NO;
    BOOL enableTunerAGC = NO;

    if (categoryDictionary == NULL)
    {
        if (frequenciesArray.count == 1)
        {
            // tune to a single Favorites frequency
            NSDictionary * firstFrequencyDictionary = frequenciesArray.firstObject;
            
            nameString = [firstFrequencyDictionary objectForKey:@"station_name"];
            categoryScanningEnabledNumber = [NSNumber numberWithInteger:0];
            samplingModeNumber = [firstFrequencyDictionary objectForKey:@"sampling_mode"];
            tunerGainNumber = [firstFrequencyDictionary objectForKey:@"tuner_gain"];
            tunerAGCNumber = [firstFrequencyDictionary objectForKey:@"tuner_agc"];
            tunerSampleRateNumber = [firstFrequencyDictionary objectForKey:@"sample_rate"];
            oversamplingNumber = [firstFrequencyDictionary objectForKey:@"oversampling"];
            modulationString = [firstFrequencyDictionary objectForKey:@"modulation"];
            squelchLevelNumber = [firstFrequencyDictionary objectForKey:@"squelch_level"];
            optionsString = [firstFrequencyDictionary objectForKey:@"options"];
            firSizeNumber = [firstFrequencyDictionary objectForKey:@"fir_size"];
            atanMathString = [firstFrequencyDictionary objectForKey:@"atan_math"];
            audioOutputFilterString = [firstFrequencyDictionary objectForKey:@"audio_output_filter"];
            audioOutputString = [firstFrequencyDictionary objectForKey:@"audio_output"];
            streamSourceString = [firstFrequencyDictionary objectForKey:@"stream_source"];

            NSNumber * frequencyModeNumber = [firstFrequencyDictionary objectForKey:@"frequency_mode"]; // 0 = single frequency, 1 = frequency range
            NSInteger frequencyMode = [frequencyModeNumber integerValue];
            
            NSString * aFrequencyString = [firstFrequencyDictionary objectForKey:@"frequency"];
            NSString * aFrequencyScanEndString = [firstFrequencyDictionary objectForKey:@"frequency_scan_end"];
            NSString * aFrequencyScanIntervalString = [firstFrequencyDictionary objectForKey:@"frequency_scan_interval"];

            frequencyString = [NSMutableString stringWithFormat:@"-f %@", aFrequencyString];

            if (frequencyMode == 1)
            {
                // use scan range start, end and interval
                frequencyString = [NSMutableString stringWithFormat:@"-f %@:%@:%@", aFrequencyString, aFrequencyScanEndString, aFrequencyScanIntervalString];
            }
            
            NSInteger samplingMode = [samplingModeNumber integerValue];
            if (samplingMode == 2)
            {
                enableDirectSamplingQBranchMode = YES;
            }
            
            NSInteger tunerAGC = [tunerAGCNumber integerValue];
            if (tunerAGC == 1)
            {
                enableTunerAGC = YES;
            }
            
            statusFunctionString = [NSString stringWithFormat:@"Tuned to %@", nameString];

            self.appDelegate.udpStatusListenerController.nowPlayingDictionary = [firstFrequencyDictionary mutableCopy];
            [self.appDelegate.udpStatusListenerController.statusCacheDictionary removeAllObjects];
        }
        else
        {
            NSLog(@"LocalRadio error - wrong frequenciesArray.count");
            statusFunctionString = @"Error: wrong frequenciesArray.count";
        }
    }
    else
    {
        // scan one or more frequencies for the category
        nameString = [categoryDictionary objectForKey:@"category_name"];
        categoryScanningEnabledNumber = [categoryDictionary objectForKey:@"category_scanning_enabled"];
        samplingModeNumber = [categoryDictionary objectForKey:@"scan_sampling_mode"];
        tunerGainNumber = [categoryDictionary objectForKey:@"scan_tuner_gain"];
        tunerAGCNumber = [categoryDictionary objectForKey:@"scan_tuner_agc"];
        tunerSampleRateNumber = [categoryDictionary objectForKey:@"scan_sample_rate"];
        oversamplingNumber = [categoryDictionary objectForKey:@"scan_oversampling"];
        modulationString = [categoryDictionary objectForKey:@"scan_modulation"];
        squelchLevelNumber = [categoryDictionary objectForKey:@"scan_squelch_level"];
        squelchDelayNumber = [categoryDictionary objectForKey:@"scan_squelch_delay"];
        optionsString = [categoryDictionary objectForKey:@"scan_options"];
        firSizeNumber = [categoryDictionary objectForKey:@"scan_fir_size"];
        atanMathString = [categoryDictionary objectForKey:@"scan_atan_math"];
        audioOutputFilterString = [categoryDictionary objectForKey:@"scan_audio_output_filter"];
        audioOutputString = [categoryDictionary objectForKey:@"scan_audio_output"];
        streamSourceString = [categoryDictionary objectForKey:@"scan_stream_source"];

        [frequencyString setString:@""];
        
        for (NSDictionary * frequencyDictionary in frequenciesArray)
        {
            NSNumber * frequencyModeNumber = [frequencyDictionary objectForKey:@"frequency_mode"]; // 0 = single frequency, 1 = frequency range
            NSInteger frequencyMode = [frequencyModeNumber integerValue];

            NSString * aFrequencyString = [frequencyDictionary objectForKey:@"frequency"];
            NSString * aFrequencyScanEndString = [frequencyDictionary objectForKey:@"frequency_scan_end"];
            NSString * aFrequencyScanIntervalString = [frequencyDictionary objectForKey:@"frequency_scan_interval"];

            NSString * aFrequencyComboString = [NSMutableString stringWithFormat:@"-f %@", aFrequencyString];
            

            if (frequencyMode == 1) // use scan range start, end and interval
            {
                aFrequencyComboString = [NSMutableString stringWithFormat:@"-f %@:%@:%@", aFrequencyString, aFrequencyScanEndString, aFrequencyScanIntervalString];
            }

            if (frequencyString.length > 0)
            {
                [frequencyString appendString:@" "];
            }
            
            //[frequencyString appendFormat:@"-f %@ ", aFrequencyComboString];
            [frequencyString appendString:aFrequencyComboString];

            if ([frequenciesArray indexOfObject:frequencyDictionary] == 0)
            {
                self.appDelegate.udpStatusListenerController.nowPlayingDictionary = [frequencyDictionary mutableCopy];
                [self.appDelegate.udpStatusListenerController.statusCacheDictionary removeAllObjects];
            }
        }

        NSInteger samplingMode = [samplingModeNumber integerValue];
        if (samplingMode == 2)
        {
            enableDirectSamplingQBranchMode = YES;
        }

        NSInteger tunerAGC = [tunerAGCNumber integerValue];
        if (tunerAGC == 1)
        {
            enableTunerAGC = YES;
        }

        statusFunctionString = [NSString stringWithFormat:@"Scanning category: %@", nameString];
    }

    self.rtlsdrTaskFrequenciesArray = frequenciesArray;
    
    NSCharacterSet * whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    audioOutputString = [audioOutputString stringByTrimmingCharactersInSet:whitespaceCharacterSet];
    streamSourceString = [streamSourceString stringByTrimmingCharactersInSet:whitespaceCharacterSet];

    TaskItem * rtlfmTaskItem = [self.radioTaskPipelineManager makeTaskItemWithExecutable:@"rtl_fm_localradio" functionName:@"rtl_fm_localradio"];

    TaskItem * audioMonitorTaskItem = [self.radioTaskPipelineManager makeTaskItemWithExecutable:@"AudioMonitor" functionName:@"AudioMonitor"];

    TaskItem * soxTaskItem = [self.radioTaskPipelineManager makeTaskItemWithExecutable:@"sox" functionName:@"sox"];

    TaskItem * udpSenderTaskItem = [self.radioTaskPipelineManager makeTaskItemWithExecutable:@"UDPSender" functionName:@"UDPSender"];
    
    [rtlfmTaskItem addArgument:@"-M"];
    [rtlfmTaskItem addArgument:modulationString];
    [rtlfmTaskItem addArgument:@"-l"];
    [rtlfmTaskItem addArgument:squelchLevelNumber.stringValue];
    [rtlfmTaskItem addArgument:@"-t"];
    [rtlfmTaskItem addArgument:squelchDelayNumber.stringValue];
    [rtlfmTaskItem addArgument:@"-F"];
    [rtlfmTaskItem addArgument:firSizeNumber.stringValue];
    [rtlfmTaskItem addArgument:@"-g"];
    [rtlfmTaskItem addArgument:tunerGainNumber.stringValue];
    [rtlfmTaskItem addArgument:@"-s"];
    [rtlfmTaskItem addArgument:tunerSampleRateNumber.stringValue];
    
    if ([oversamplingNumber integerValue] > 0)
    {
        [rtlfmTaskItem addArgument:@"-o"];
        [rtlfmTaskItem addArgument:oversamplingNumber];
    }
    
    [rtlfmTaskItem addArgument:@"-A"];
    [rtlfmTaskItem addArgument:atanMathString];
    [rtlfmTaskItem addArgument:@"-p"];
    [rtlfmTaskItem addArgument:@"0"];
    [rtlfmTaskItem addArgument:@"-c"];
    [rtlfmTaskItem addArgument:statusPortNumber.stringValue];

    [rtlfmTaskItem addArgument:@"-E"];
    [rtlfmTaskItem addArgument:@"pad"];
    
    if (enableDirectSamplingQBranchMode == YES)
    {
        [rtlfmTaskItem addArgument:@"-E"];
        [rtlfmTaskItem addArgument:@"direct"];
    }
    
    if (enableTunerAGC == YES)
    {
        [rtlfmTaskItem addArgument:@"-E"];
        [rtlfmTaskItem addArgument:@"agc"];
    }
    
    NSArray * optionsArray = [optionsString componentsSeparatedByString:@" "];
    for (NSString * aOptionString in optionsArray)
    {
        NSString * trimmedOptionString = [aOptionString stringByTrimmingCharactersInSet:whitespaceCharacterSet];
        if (trimmedOptionString.length > 0)
        {
            [rtlfmTaskItem addArgument:@"-E"];
            [rtlfmTaskItem addArgument:trimmedOptionString];
        }
    }
    
    NSArray * parsedFrequenciesArray = [frequencyString componentsSeparatedByString:@" "];
    for (NSString * parsedItem in parsedFrequenciesArray)
    {
        [rtlfmTaskItem addArgument:parsedItem];
    }
    
    [audioMonitorTaskItem addArgument:@"-r"];
    [audioMonitorTaskItem addArgument:tunerSampleRateNumber.stringValue];

    NSString * livePlaythroughVolume = @"0.0";
    if (self.appDelegate.useWebViewAudioPlayerCheckbox.state == NO)
    {
        livePlaythroughVolume = @"1.0";
    }
    [audioMonitorTaskItem addArgument:@"-v"];
    [audioMonitorTaskItem addArgument:livePlaythroughVolume];
    
    BOOL useSecondaryStreamSource = NO;
    
    if ([audioOutputString isEqualToString:@"icecast"])
    {
        // configure rtl_fm_localradio for output to UDPSender (then to EZStream/Icecast)
        
        [soxTaskItem addArgument:@"-r"];
        [soxTaskItem addArgument:@"48000"];      // assume input from AudioMonitor already resampled to 48000 Hz
        
        [soxTaskItem addArgument:@"-e"];
        [soxTaskItem addArgument:@"signed-integer"];
        
        [soxTaskItem addArgument:@"-b"];
        [soxTaskItem addArgument:@"16"];
        
        [soxTaskItem addArgument:@"-c"];
        [soxTaskItem addArgument:@"1"];
        
        [soxTaskItem addArgument:@"-t"];
        [soxTaskItem addArgument:@"raw"];
        
        [soxTaskItem addArgument:@"-"];         // stdin
        
        [soxTaskItem addArgument:@"-t"];
        [soxTaskItem addArgument:@"raw"];
        
        [soxTaskItem addArgument:@"-"];         // stdout
        
        [soxTaskItem addArgument:@"rate"];
        [soxTaskItem addArgument:@"48000"];
        
        NSArray * audioOutputFilterStringArray = [audioOutputFilterString componentsSeparatedByString:@" "];
        for (NSString * audioOutputFilterStringItem in audioOutputFilterStringArray)
        {
            [soxTaskItem addArgument:audioOutputFilterStringItem];
        }

        // configure UDPSender task

        [udpSenderTaskItem addArgument:@"-p"];
        NSNumber * audioPortNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"AudioPort"];
        [udpSenderTaskItem addArgument:audioPortNumber.stringValue];
    }
    else
    {
        // configure rtl_fm_localradio for output to a Core Audio device
        // audioOutputString should be a Core Audio output devicename
        // and start a secondary sox task to relay from a different Core Audio device to UDPSender
        // This can be useful with some third-party audio routing utilities, like SoundFlower
        
        [soxTaskItem addArgument:@"-V2"];    // debug verbosity, -V2 shows failures and warnings
        [soxTaskItem addArgument:@"-q"];    // quiet mode - don't show terminal-style audio meter
        
        // input args

        [soxTaskItem addArgument:@"-r"];
        [soxTaskItem addArgument:@"48000"];      // assume input from AudioMonitor already resampled to 48000 Hz
        
        [soxTaskItem addArgument:@"-e"];
        [soxTaskItem addArgument:@"signed-integer"];
        
        [soxTaskItem addArgument:@"-b"];
        [soxTaskItem addArgument:@"16"];
        
        [soxTaskItem addArgument:@"-c"];
        [soxTaskItem addArgument:@"1"];
        
        [soxTaskItem addArgument:@"-t"];
        [soxTaskItem addArgument:@"raw"];
        
        [soxTaskItem addArgument:@"-"];         // stdin

        // output args
        
        [soxTaskItem addArgument:@"-e"];
        [soxTaskItem addArgument:@"float"];
        
        [soxTaskItem addArgument:@"-b"];
        [soxTaskItem addArgument:@"32"];
        
        [soxTaskItem addArgument:@"-c"];
        [soxTaskItem addArgument:@"2"];
        
        // send output to a Core Audio device
        [soxTaskItem addArgument:@"-t"];

        [soxTaskItem addArgument:@"coreaudio"];       // first stage audio output
        [soxTaskItem addArgument:audioOutputString];  // quotes are omitted intentionally
        
        [soxTaskItem addArgument:@"rate"];
        [soxTaskItem addArgument:@"48000"];

        // output sox options like vol, etc.
        NSArray * audioOutputFilterStringArray = [audioOutputFilterString componentsSeparatedByString:@" "];
        for (NSString * audioOutputFilterStringItem in audioOutputFilterStringArray)
        {
            [soxTaskItem addArgument:audioOutputFilterStringItem];
        }

        useSecondaryStreamSource = YES;     // create a separate task to get audio to EZStream
    }


    // TODO: BUG: For an undetermined reason, AudioMonitor fails to launch as an NSTask in a sandboxed app extracted from an Xcode Archive
    // if the application path contains a space (e.g., "~/Untitled Folder/LocalRadio.app".
    // Prefixing backslashes before spaces in the path did not help.  The error message in Console.log says "launch path not accessible".
    // As a workaround, alert the user if the condition exists and suggest removing the spaces from the folder name.

    
    @synchronized (self.radioTaskPipelineManager)
    {
        [self.radioTaskPipelineManager addTaskItem:rtlfmTaskItem];
        [self.radioTaskPipelineManager addTaskItem:audioMonitorTaskItem];
        [self.radioTaskPipelineManager addTaskItem:soxTaskItem];
        
        if (useSecondaryStreamSource == NO)
        {
            // send audio to EZStream/icecast
            [self.radioTaskPipelineManager addTaskItem:udpSenderTaskItem];
        }
        else
        {
            // send audio to user-specified output device for external processing in a separate app
            [self.appDelegate.soxController startSecondaryStreamForFrequencies:frequenciesArray category:categoryDictionary];
        }
    }

    [self.radioTaskPipelineManager startTasks];
    
    SDRController * weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
    
        [weakSelf.appDelegate updateCurrentTasksText];
        
        self.appDelegate.statusRTLSDRTextField.stringValue = @"Running";

        self.appDelegate.statusFunctionTextField.stringValue = statusFunctionString;
        
        NSString * displayFrequencyString = [NSString stringWithFormat:@"%@", frequencyString];
        displayFrequencyString = [displayFrequencyString stringByReplacingOccurrencesOfString:@"-f " withString:@""];
        NSString * megahertzString = [self.appDelegate shortHertzString:displayFrequencyString];
        self.appDelegate.statusFrequencyTextField.stringValue = megahertzString;
        
        self.appDelegate.statusModulationTextField.stringValue = modulationString;
        self.appDelegate.statusSamplingRateTextField.stringValue = tunerSampleRateNumber.stringValue;
        self.appDelegate.statusSquelchLevelTextField.stringValue = squelchLevelNumber.stringValue;
        self.appDelegate.statusTunerGainTextField.stringValue = [NSString stringWithFormat:@"%@", tunerGainNumber];
        self.appDelegate.statusRtlsdrOptionsTextField.stringValue = optionsString;
        self.appDelegate.statusSignalLevelTextField.stringValue = @"0";
        self.appDelegate.statusAudioOutputTextField.stringValue = audioOutputString;
        self.appDelegate.statusAudioOutputFilterTextField.stringValue = audioOutputFilterString;
        self.appDelegate.statusStreamSourceTextField.stringValue = streamSourceString;
        
        if (enableTunerAGC == YES)
        {
            self.appDelegate.statusTunerAGCTextField.stringValue = @"On";
        }
        else
        {
            self.appDelegate.statusTunerAGCTextField.stringValue = @"Off";
        }
        
        if (enableDirectSamplingQBranchMode == NO)
        {
            self.appDelegate.statusSamplingModeTextField.stringValue = @"Standard";
        }
        else
        {
            self.appDelegate.statusSamplingModeTextField.stringValue = @"Direct Q-branch";
        }
    });

}

//==================================================================================
//	radioTaskReceivedStderrData:
//==================================================================================

- (void)radioTaskReceivedStderrData:(NSNotification *)notif {

    NSFileHandle *fh = [notif object];
    NSData *data = [fh availableData];
    if (data.length > 0)
    {
        // if data is found, re-register for more data (and print)
        //[fh waitForDataInBackgroundAndNotify];
        NSString * str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"rtlsdr: %@" , str);
    }
    [fh waitForDataInBackgroundAndNotify];
}

//==================================================================================
//	retuneTaskForFrequency:
//==================================================================================
/*
- (void)retuneTaskForFrequency:(NSDictionary *)frequencyDictionary
{
    char retuneCommand[5];
    
    NSData * udpData = NULL;

    // begin retuning
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 0;
    int beginRetuningInteger = 0;
    memcpy(&retuneCommand[1], &beginRetuningInteger, sizeof(beginRetuningInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set modulation
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 1;
    char modulationMode = 0;
    NSString * modulationString = [frequencyDictionary objectForKey:@"modulation"];
    if ([modulationString isEqualToString:@"fm"] == YES)
    {
        modulationMode = 0;
    }
    else if ([modulationString isEqualToString:@"wbfm"] == YES)
    {
        modulationMode = 0;
    }
    else if ([modulationString isEqualToString:@"am"] == YES)
    {
        modulationMode = 1;
    }
    else if ([modulationString isEqualToString:@"usb"] == YES)
    {
        modulationMode = 2;
    }
    else if ([modulationString isEqualToString:@"lsb"] == YES)
    {
        modulationMode = 3;
    }
    retuneCommand[1] = modulationMode;
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set sample rate
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 2;
    NSNumber * sampleRateNumber = [frequencyDictionary objectForKey:@"sample_rate"];
    int sampleRateInteger = sampleRateNumber.intValue;
    memcpy(&retuneCommand[1], &sampleRateInteger, sizeof(sampleRateInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set tuner gain
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 4;
    NSNumber * tunerGainNumber = [frequencyDictionary objectForKey:@"tuner_gain"];
    int tunerGainInteger = tunerGainNumber.intValue;
    memcpy(&retuneCommand[1], &tunerGainInteger, sizeof(tunerGainInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set automatic gain control
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 5;
    NSNumber * agcNumber = [frequencyDictionary objectForKey:@"automatic_gain_control"];
    int agcInteger = agcNumber.intValue;
    memcpy(&retuneCommand[1], &agcInteger, sizeof(tunerGainInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set squelch level
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 6;
    NSNumber * squelchLevelNumber = [frequencyDictionary objectForKey:@"squelch_level"];
    int squelchLevelInteger = squelchLevelNumber.intValue;
    memcpy(&retuneCommand[1], &squelchLevelInteger, sizeof(squelchLevelInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
    
    // set frequency
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 7;
    NSNumber * frequencyNumber = [frequencyDictionary objectForKey:@"frequency"];
    int frequencyInteger = frequencyNumber.intValue;
    memcpy(&retuneCommand[1], &frequencyInteger, sizeof(frequencyInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);

    // end retuning
    bzero(&retuneCommand, sizeof(retuneCommand));
    retuneCommand[0] = 8;
    int endRetuningInteger = 0;
    memcpy(&retuneCommand[1], &endRetuningInteger, sizeof(endRetuningInteger));
    udpData = [[NSData alloc] initWithBytes:&retuneCommand length:sizeof(retuneCommand)];
    [self.udpSocket sendData:udpData toHost:@"127.0.0.1" port:6020 withTimeout:0 tag:self.udpTag++];
    //usleep(100000);
}
*/



@end
