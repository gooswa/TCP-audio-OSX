//
//  AudioSource.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//


#import "AudioSource.h"
#import <CoreAudio/CoreAudio.h>

#define FRAMES 1024
#define CHANNELS 8
#define NUM_BUFFERS 3

NSString *audioSourceNameKey = @"audioSourceName";
NSString *audioSourceNominalSampleRateKey = @"audioSourceNominalSampleRate";
NSString *audioSourceAvailableSampleRatesKey = @"audioSourceAvailableSampleRates";
NSString *audioSourceInputChannelsKey = @"audioSourceInputChannels";
NSString *audioSourceOutputChannelsKey = @"audioSourceOutputChannels";
NSString *audioSourceDeviceIDKey = @"audioSourceDeviceID";

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
	
//	if( inNumPackets == 0 && recorderState->mDataFormat.mBytesPerPacket != 0 )
//		inNumPackets = inBuffer->mAudioDataByteSize / recorderState->mDataFormat.mBytesPerPacket;
	
	if( [recorderState->audioSource running] ) {		
		[recorderState->delegate audioData:inBuffer->mAudioData
                                      size:inBuffer->mAudioDataByteSize];
	}
    
    else {
		NSLog(@"Discarded AudioQueue buffer (network connection closed)");
	}
    
    // Return the buffer to the audio queue
	AudioQueueEnqueueBuffer(recorderState->mQueue, inBuffer, 0, 0);
}

@implementation AudioSource

@synthesize initialized;
@synthesize devices;

- (id)init
{	
	self = [super init];
	
	if( self == nil ) {
		NSLog(@"Error initializing superclass for AudioSource.");
		return self;
	}
	
    // Variables used for each of the functions
    uint32 propertySize = 0;
    Boolean writable = NO;
    AudioObjectPropertyAddress property;
    
    // Get the size of the device IDs array
    property.mSelector = kAudioHardwarePropertyDevices;
    property.mScope    = kAudioObjectPropertyScopeGlobal;
    property.mElement  = kAudioObjectPropertyElementMaster;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                   &property, 0, NULL, &propertySize);
    
    // Create the array for device IDs
    AudioDeviceID *deviceIDs = (AudioDeviceID *)malloc(propertySize);
    
    // Get the device IDs
    AudioObjectGetPropertyData(kAudioObjectSystemObject, 
                               &property, 0, NULL, 
                               &propertySize, deviceIDs);
    
    NSUInteger numDevices = propertySize / sizeof(AudioDeviceID);
    
    // This is the array to hold the NSDictionaries
    devices = [[NSMutableArray alloc] initWithCapacity:numDevices];
    
    // Get per-device information
    for (int i = 0; i < numDevices; i++) {
        NSMutableDictionary *deviceDict = [[NSMutableDictionary alloc] init];
        [deviceDict setValue:[NSNumber numberWithInt:i]
                                              forKey:audioSourceDeviceIDKey];
        
        CFStringRef string;

        // Get the name of the audio device
        property.mSelector = kAudioObjectPropertyName;
        property.mScope    = kAudioObjectPropertyScopeGlobal;
        property.mElement  = kAudioObjectPropertyElementMaster;

        propertySize = sizeof(string);
        AudioObjectGetPropertyData(deviceIDs[i], &property, 0, NULL, 
                                   &propertySize, &string);

        // Even though it's probably OK to use the CFString as an NSString
        // I'm going to make a copy, just to be safe.
        NSString *deviceName = [(NSString *)string copy];
        CFRelease(string);
        
        [deviceDict setValue:deviceName
                      forKey:audioSourceNameKey];

        // The string given from the property has +1 retain,
        // we need to make sure that we release it.
        [deviceName release];
        
        Float64 currentSampleRate = 0;
        propertySize = sizeof(currentSampleRate);
        AudioDeviceGetProperty(deviceIDs[i], 0, NO, 
                               kAudioDevicePropertyNominalSampleRate,
                               &propertySize, &currentSampleRate);

//        NSLog(@"Device %d: %@ @ %1.1f", i, deviceName, currentSampleRate);

        [deviceDict setValue:[NSNumber numberWithFloat:currentSampleRate]
                      forKey:audioSourceNominalSampleRateKey];
        
        // Using stream objects
/*        AudioDeviceGetPropertyInfo(devices[i], 0, NO, 
                                   kAudioDevicePropertyStreams, 
                                   &propertySize, &writable);
        AudioStreamID *streams = malloc(propertySize);
        AudioDeviceGetProperty(devices[i], 0, NO, 
                               kAudioDevicePropertyStreams, 
                               &propertySize, streams);
        NSUInteger numStreams = propertySize / sizeof(AudioDeviceID);
        for (int j = 0; j < numStreams; j++) {
            uint32 direction = -1;
            propertySize = sizeof(direction);
            AudioStreamGetProperty(streams[j], 0, 
                                   kAudioStreamPropertyDirection, 
                                   &propertySize, &direction);
            if (direction == 0) {
                NSLog(@"Stream %d is an output.", j);
            } else {
                NSLog(@"Stream %d is an input.", j);
            }
        }
*/        

        // Get an array of sample rates
        AudioValueRange *sampleRates;
        AudioDeviceGetPropertyInfo(deviceIDs[i], 0, NO, 
                                   kAudioDevicePropertyAvailableNominalSampleRates, 
                                   &propertySize, &writable);
        sampleRates = (AudioValueRange *)malloc(propertySize);
        AudioDeviceGetProperty(deviceIDs[i], 0, NO, 
                               kAudioDevicePropertyAvailableNominalSampleRates, 
                               &propertySize, sampleRates);
        
        NSUInteger numSampleRates = propertySize / sizeof(AudioValueRange);
        NSMutableArray *sampleRateTempArray = [[NSMutableArray alloc] init];
        for (int j = 0; j < numSampleRates; j++) {
            // An NSRange is a location and length...
            NSRange sampleRange;
            sampleRange.length   = sampleRates[j].mMaximum - sampleRates[j].mMinimum;
            sampleRange.location = sampleRates[j].mMinimum;
            
            [sampleRateTempArray addObject:[NSValue valueWithRange:sampleRange]];
//            NSLog(@"Sample rate range %d: %f - %f", j,
//                  sampleRates[j].mMinimum,
//                  sampleRates[j].mMinimum);
        }
        
        // Create a immutable copy of the available sample rate array
        // and store it into the NSDict
        NSArray *tempArray = [sampleRateTempArray copy];
        [sampleRateTempArray release];
        [deviceDict setValue:tempArray
                      forKey:audioSourceAvailableSampleRatesKey];
        [tempArray release];
        
        // Get the number of output channels for the device
        AudioBufferList bufferList;
        propertySize = sizeof(bufferList);
        AudioDeviceGetProperty(deviceIDs[i], 0, NO, 
                               kAudioDevicePropertyStreamConfiguration, 
                               &propertySize, &bufferList);
        
        int outChannels, inChannels;
        if (bufferList.mNumberBuffers > 0) {
            outChannels = bufferList.mBuffers[0].mNumberChannels;
//            NSLog(@"%d output channels.", outChannels);
            [deviceDict setValue:[NSNumber numberWithInt:outChannels]
                          forKey:audioSourceOutputChannelsKey];
        } else {
            [deviceDict setValue:[NSNumber numberWithInt:0]
                          forKey:audioSourceOutputChannelsKey];            
        }

        // Again for input channels
        propertySize = sizeof(bufferList);
        AudioDeviceGetProperty(deviceIDs[i], 0, YES, 
                               kAudioDevicePropertyStreamConfiguration, 
                               &propertySize, &bufferList);
        
        // The number of channels is the number of buffers.
        // The actual buffers are NULL.
        if (bufferList.mNumberBuffers > 0) {
            inChannels = bufferList.mBuffers[0].mNumberChannels;
//            NSLog(@"%d input channels.", inChannels);
            [deviceDict setValue:[NSNumber numberWithInt:inChannels]
                          forKey:audioSourceInputChannelsKey];
        } else {
            [deviceDict setValue:[NSNumber numberWithInt:0]
                          forKey:audioSourceInputChannelsKey];
        }
        
        // Add this new device dict to the array and release it
        [devices addObject:deviceDict];
        [deviceDict release];
    }
    
    return self;
}

- (bool)createAudioSource
{
    // Keep a self-referential pointer in recorderState
	recorderState.audioSource = self;
	
    // Setup the desired parameters from the Audio Queue
	recorderState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
	recorderState.mDataFormat.mSampleRate = 96000.0;
	recorderState.mDataFormat.mChannelsPerFrame = 2;
	recorderState.mDataFormat.mBitsPerChannel = 32;
	recorderState.mDataFormat.mBytesPerPacket =
    recorderState.mDataFormat.mBytesPerFrame =
    recorderState.mDataFormat.mChannelsPerFrame * 4;    // 4-byte samples (32 bit)
	recorderState.mDataFormat.mFramesPerPacket = 1;
	recorderState.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat;
    
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
	NSString *deviceString;
    if( result == kAudioHardwareNoError ) {
		UInt32 dataFormatSize = sizeof( recorderState.mDataFormat );
		AudioQueueGetProperty(recorderState.mQueue,
							  kAudioConverterCurrentInputStreamDescription,
							  &recorderState.mDataFormat, &dataFormatSize);
        
		dataFormatSize = sizeof(device_UID);
        AudioQueueGetProperty(recorderState.mQueue,
							  kAudioQueueProperty_CurrentDevice,
							  &device_UID, &dataFormatSize);

        deviceString = (NSString *)device_UID;
    }
    
    // We got some error creating the input
    else {
        initialized = NO;
        return NO;
    }
    
	NSLog(@"Using audio device UID: %@\n", deviceString);
	NSLog(@"Got channel count %d from driver.\n", recorderState.mDataFormat.mChannelsPerFrame);
	
    // Allocate buffer list, buffers and provide to audioQueue
	recorderState.mBuffers = (AudioQueueBufferRef *)malloc(sizeof(AudioQueueBufferRef *) * NUM_BUFFERS);
	for( int i = 0; i < NUM_BUFFERS; i++ ) {
		AudioQueueAllocateBuffer(recorderState.mQueue, FRAMES*CHANNELS*sizeof(SInt16), &recorderState.mBuffers[i]);
		AudioQueueEnqueueBuffer (recorderState.mQueue, recorderState.mBuffers[i], 0, NULL);
	}
	
	initialized = YES;
	
	return YES;
}

- (void)startAudio
{
	NSLog(@"Audio Start Request.");

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
