//
//  AudioSource.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//


#import "AudioSource.h"
#import <CoreAudio/CoreAudio.h>

#define FRAMES      1024
#define NUM_BUFFERS 4

NSString *audioSourceNameKey = @"audioSourceName";
NSString *audioSourceNominalSampleRateKey = @"audioSourceNominalSampleRate";
NSString *audioSourceAvailableSampleRatesKey = @"audioSourceAvailableSampleRates";
NSString *audioSourceInputChannelsKey = @"audioSourceInputChannels";
NSString *audioSourceOutputChannelsKey = @"audioSourceOutputChannels";
NSString *audioSourceDeviceIDKey = @"audioSourceDeviceID";
NSString *audioSourceDeviceUIDKey = @"audioSourceDeviceUID";

void handleInputBuffer(void *aqData,
                       AudioQueueRef audioQueue,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *packetDesc)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
	struct AQRecorderState *recorderState = (struct AQRecorderState *)aqData;
	
//	if( inNumPackets == 0 && recorderState->mDataFormat.mBytesPerPacket != 0 )
//		inNumPackets = inBuffer->mAudioDataByteSize / recorderState->mDataFormat.mBytesPerPacket;
	
	if( [recorderState->audioSource running] ) {		
		[recorderState->delegate audioBytes:inBuffer->mAudioData
                                       size:inBuffer->mAudioDataByteSize];
	}
    
//    else {
//		NSLog(@"Discarded AudioQueue buffer (network connection closed)");
//	}
    
    // Return the buffer to the audio queue
	AudioQueueEnqueueBuffer(recorderState->mQueue, inBuffer, 0, 0);
    
    [pool drain];
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
	
    delegate = nil;
    recorderState.mBuffers = nil;
    
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
        
    // Get the UID of the device, used by the audioQueue
        property.mSelector = kAudioDevicePropertyDeviceUID;
        propertySize = sizeof(string);
        AudioObjectGetPropertyData(deviceIDs[i], &property, 0, NULL, 
                                   &propertySize, &string);
        
        // Again, copy to a NSString...
        NSString *deviceUID = [(NSString *)string copy];
        CFRelease(string);
        [deviceDict setValue:deviceUID
                      forKey:audioSourceDeviceUIDKey];
        [deviceUID release];
        
    // Get the nominal sample rate
        Float64 currentSampleRate = 0;
        propertySize = sizeof(currentSampleRate);
        AudioDeviceGetProperty(deviceIDs[i], 0, NO, 
                               kAudioDevicePropertyNominalSampleRate,
                               &propertySize, &currentSampleRate);


        [deviceDict setValue:[NSNumber numberWithFloat:currentSampleRate]
                      forKey:audioSourceNominalSampleRateKey];
        
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
        }
        
        // Create a immutable copy of the available sample rate array
        // and store it into the NSDict
        NSArray *tempArray = [sampleRateTempArray copy];
        [sampleRateTempArray release];
        [deviceDict setValue:tempArray
                      forKey:audioSourceAvailableSampleRatesKey];
        [tempArray release];
        free(sampleRates);
        
    // Get the number of output channels for the device
        AudioBufferList bufferList;
        propertySize = sizeof(bufferList);
        AudioDeviceGetProperty(deviceIDs[i], 0, NO, 
                               kAudioDevicePropertyStreamConfiguration, 
                               &propertySize, &bufferList);
        
        int outChannels, inChannels;
        if (bufferList.mNumberBuffers > 0) {
            outChannels = bufferList.mBuffers[0].mNumberChannels;
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
    
    free(deviceIDs);
    
    return self;
}

- (void)dealloc
{
    free(recorderState.mBuffers);
    [devices release];
}

//- (void)setDelegate:(id <audioSourceDelegate>)inDelegate
- (void)setDelegate:(id)inDelegate
{
    if (delegate != nil) {
        [delegate release];
    }
    
    delegate = [inDelegate retain];
}

- (void)setDevice:(int)inDevice
{
    device = inDevice;
}

- (void)setSampleRate:(float)inSampleRate
{
    sampleRate = inSampleRate;
}

- (void)setChannels:(int)inChannels
{
    channels = inChannels;
}

- (uint32)deriveBufferSizeforQueue:(AudioQueueRef)queue
                       description:(AudioStreamBasicDescription)desc
                        andSeconds:(Float64)secs
{
    static const int maxBufferSize = 327680;
    
    int maxPacketSize = desc.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(queue, 
                              kAudioConverterPropertyMaximumOutputPacketSize, 
                              &maxPacketSize, &maxVBRPacketSize);
    }
    
    Float64 numBytesForTime = desc.mSampleRate * maxPacketSize * secs;
    return (uint32)(numBytesForTime < maxBufferSize) ? numBytesForTime : maxBufferSize;
}

- (bool)startAudio
{
	NSLog(@"Audio Start Request.");

    // Keep a self-referential pointer in recorderState
	recorderState.audioSource = self;
	
    // Set the delegate
    recorderState.delegate = delegate;
    
// Setup the desired parameters from the Audio Queue
	recorderState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
	recorderState.mDataFormat.mSampleRate = sampleRate;
	recorderState.mDataFormat.mChannelsPerFrame = channels;
	recorderState.mDataFormat.mBitsPerChannel = 8 * sizeof(Float32);
	recorderState.mDataFormat.mBytesPerPacket = channels * sizeof(Float32);
    recorderState.mDataFormat.mBytesPerFrame  = channels * sizeof(Float32);
	recorderState.mDataFormat.mFramesPerPacket = 1;
	recorderState.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat |
                                             kLinearPCMFormatFlagIsPacked;
    
// Create the new Audio Queue
	OSStatus result = AudioQueueNewInput(&recorderState.mDataFormat,
										 handleInputBuffer,
                                         &recorderState,
										 NULL,
                                         kCFRunLoopCommonModes,
                                         0,
										 &recorderState.mQueue);
	if (result != kAudioHardwareNoError) {
        NSLog(@"Unable to create new input audio queue.");
        return NO;
    }
    
// Set the device for this audioQueue
    NSDictionary *deviceDict = [devices objectAtIndex:device];
    CFStringRef   deviceUID;
    deviceUID = (CFStringRef)[deviceDict objectForKey:audioSourceDeviceUIDKey];
    UInt32 propertySize = sizeof(CFStringRef);
    result = AudioQueueSetProperty(recorderState.mQueue, 
                                   kAudioQueueProperty_CurrentDevice, 
                                   &deviceUID, propertySize);
    
    if (result != kAudioHardwareNoError) {
        NSLog(@"Unable to set audio queue device to %@", deviceUID);
        return NO;
    }
    
	NSLog(@"Using audio device UID: %@\n", deviceUID);
	
    // Get the basic description through the API to check everything
    propertySize = sizeof(recorderState.mDataFormat);
    result = AudioQueueGetProperty(recorderState.mQueue, 
                                   kAudioQueueProperty_StreamDescription, 
                                   &recorderState.mDataFormat, 
                                   &propertySize);
    if (result != kAudioHardwareNoError) {
        NSLog(@"Unable to get audio basic format");
        return NO;
    }
    
    // Get the proper buffer size
    uint32 bufferSize = [self deriveBufferSizeforQueue:recorderState.mQueue
                                           description:recorderState.mDataFormat
                                            andSeconds:1.];
    
    // Allocate buffer list, buffers and provide to audioQueue
    if (recorderState.mBuffers == nil) {
        recorderState.mBuffers = (AudioQueueBufferRef *)malloc(sizeof(AudioQueueBufferRef *) * NUM_BUFFERS);
        for( int i = 0; i < NUM_BUFFERS; i++ ) {
            AudioQueueAllocateBuffer(recorderState.mQueue,
                                     bufferSize,
                                     &recorderState.mBuffers[i]);
            AudioQueueEnqueueBuffer (recorderState.mQueue,
                                     recorderState.mBuffers[i], 0, NULL);
        }
    }
    
    AudioQueueStart(recorderState.mQueue, NULL);		
    running = true;
    return YES;
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
