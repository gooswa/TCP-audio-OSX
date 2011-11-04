//
//  AudioSource.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//


#import "AudioSource.h"

#define FRAMES 1024
#define CHANNELS 8
#define NUM_BUFFERS 3

// define a C struct from the Obj-C object so audio callback can access data
/*
 typedef struct {
 @defs(AudioSource);
 } audiosourcedef;
 */

void handleInputBuffer(void *aqData,
                       AudioQueueRef audioQueue,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *packetDesc)
{
	struct AQRecorderState *recorderState = (struct AQRecorderState *)aqData;
	
	if( inNumPackets == 0 && recorderState->mDataFormat.mBytesPerPacket != 0 )
		inNumPackets = inBuffer->mAudioDataByteSize / recorderState->mDataFormat.mBytesPerPacket;
	
	if( [recorderState->audioSource running] ) {
		
        //		NSLog(@"Sending %d bytes of data", inBuffer->mAudioDataByteSize);
		[recorderState->session send:inBuffer->mAudioDataByteSize bytes:inBuffer->mAudioData];
        
	} else {
		NSLog(@"Discarded AudioQueue buffer (network connection closed)");
	}
    
    // Return the buffer to the audio queue
	AudioQueueEnqueueBuffer(recorderState->mQueue, inBuffer, 0, 0);		
	
}

@implementation AudioSource

+ (NSArray *)getDeviceList
{
    //    AudioDeviceID
    return nil;
}

@synthesize initialized;

- (id)init
{	
	int i;
	self = [super init];
	
	if( self == nil ) {
		NSLog(@"Error initializing superclass for AudioSource.");
		return self;
	}
	
    // Keep a self-referential pointer in recorderState
	recorderState.audioSource = self;
	
    // Setup the desired parameters from the Audio Queue
	recorderState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
	recorderState.mDataFormat.mSampleRate = 44100.0;
	recorderState.mDataFormat.mChannelsPerFrame = CHANNELS;
	recorderState.mDataFormat.mBitsPerChannel = 16;
	recorderState.mDataFormat.mBytesPerPacket =
    recorderState.mDataFormat.mBytesPerFrame =
    recorderState.mDataFormat.mChannelsPerFrame * 2;    // 2-byte samples (16 bit)
	recorderState.mDataFormat.mFramesPerPacket = 1;
	recorderState.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian |
    kLinearPCMFormatFlagIsSignedInteger |
    kLinearPCMFormatFlagIsPacked;
    
    // Create the new Audio Queue
	OSStatus result = AudioQueueNewInput(&recorderState.mDataFormat,
										 handleInputBuffer,
                                         &recorderState,
										 NULL,
                                         kCFRunLoopCommonModes,
                                         0,
										 &recorderState.mQueue);
	
	// Get the full audio format from the AudioQueue
	CFStringRef device_UID;
	if( result == kAudioHardwareNoError ) {
		UInt32 dataFormatSize = sizeof( recorderState.mDataFormat );
		AudioQueueGetProperty(recorderState.mQueue,
							  kAudioConverterCurrentInputStreamDescription,
							  &recorderState.mDataFormat, &dataFormatSize);
        
		dataFormatSize = sizeof(device_UID);
        AudioQueueGetProperty(recorderState.mQueue,
							  kAudioQueueProperty_CurrentDevice,
							  &device_UID, &dataFormatSize);
	}
    
	NSString *deviceString = (__bridge_transfer NSString *)device_UID;
	NSLog(@"Using audio device UID: %@\n", deviceString);
	NSLog(@"Got channel count %d from driver.\n", recorderState.mDataFormat.mChannelsPerFrame);
	
    // Allocate buffer list, buffers and provide to audioQueue
	recorderState.mBuffers = (AudioQueueBufferRef *)malloc(sizeof(AudioQueueBufferRef *) * NUM_BUFFERS);
	for( i = 0; i < NUM_BUFFERS; i++ ) {
		AudioQueueAllocateBuffer(recorderState.mQueue, FRAMES*CHANNELS*sizeof(SInt16), &recorderState.mBuffers[i]);
		AudioQueueEnqueueBuffer (recorderState.mQueue, recorderState.mBuffers[i], 0, NULL);
	}
	
	initialized = YES;
	
	return self;
}

- (void)setSession:(NetworkSession *)newSession
{
	session = newSession;
	recorderState.session = newSession;
}

- (void)startAudio
{
	if( initialized ) {
		running = true;
		
		AudioQueueStart(recorderState.mQueue, NULL);		
	}
}

- (void)stopAudio
{
	NSLog(@"Audio Stop Request.");
	
	running = false;
	
	AudioQueueStop(recorderState.mQueue, YES);
}

- (bool)running
{
	return running;
}

@end
