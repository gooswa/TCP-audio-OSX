//
//  AudioSource.h
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//


#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioConverter.h>
#import <CoreAudio/AudioHardware.h>
#import "NetworkSession.h"

extern NSString *audioSourceNameKey;
extern NSString *audioSourceNominalSampleRateKey;
extern NSString *audioSourceAvailableSampleRatesKey;
extern NSString *audioSourceInputChannelsKey;
extern NSString *audioSourceOutputChannelsKey;
extern NSString *audioSourceDeviceIDKey;

@class AppDelegate;
@class AudioSource;

void handleInputBuffer(void *aqData,
                       AudioQueueRef audioQueue,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *packetDesc);

struct AQRecorderState {	
    AudioStreamBasicDescription  mDataFormat;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef         *mBuffers;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    AppDelegate                 *delegate;
    AudioSource                 *audioSource;
};

@interface AudioSource : NSObject {
	
	struct AQRecorderState		 recorderState;
	
	bool						 running;
	bool						 initialized;
    
	id							 delegate;
	NetworkSession				*session;
	
    NSMutableArray              *devices;
    
	// Core Audio device
	AudioDeviceID				 device;
    // Size of the audio buffer for device
	UInt32						 deviceBufferSize;
    // info about the default device
	AudioStreamBasicDescription	 deviceFormat;
};

@property(readonly) bool        running;
@property(readonly) bool        initialized;
@property(readonly) NSArray    *devices;

- (id)init;

- (void)setSession: (NetworkSession *)newSession;

- (void)startAudio;
- (void)stopAudio;

@end