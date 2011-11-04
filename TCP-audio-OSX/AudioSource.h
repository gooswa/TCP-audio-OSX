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

@class ViewController;
@class AudioSource;

void handleInputBuffer(void *aqData,
                       AudioQueueRef audioQueue,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *packetDesc);

struct AQRecorderState {	
    AudioStreamBasicDescription          mDataFormat;
    AudioQueueRef                        mQueue;
    AudioQueueBufferRef                 *mBuffers;
    UInt32                               bufferByteSize;
    SInt64                               mCurrentPacket;
	__unsafe_unretained NetworkSession  *session;
	__unsafe_unretained AudioSource     *audioSource;
};

@interface AudioSource : NSObject {
	
	struct AQRecorderState		 recorderState;
	
	bool						 running;
	bool						 initialized;
    
	id							 delegate;
	NetworkSession				*session;
	
	// Core Audio device
	AudioDeviceID				 device;
	UInt32						 deviceBufferSize;  // Size of the audio buffer for device
	AudioStreamBasicDescription	 deviceFormat;      // info about the default device
};

@property(readonly) bool running;
@property(readonly) bool initialized;

- (id)init;

- (void)setSession: (NetworkSession *)newSession;

- (void)startAudio;
- (void)stopAudio;

@end