//
//  AppDelegate.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import "AppDelegate.h"

// Convenience function used to disable the generation of a pipe signal
// when a pipe breaks.  Expect to get an EPIPE return from send/receive
// in this case.
int ignoreSigPipe();

@implementation AppDelegate

@synthesize window = _window;

#pragma mark -
#pragma mark NSApp Delegate Methods
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSLog(@"Application finished launching");
    
    sigset_t newSigSet;
    
    sigemptyset(&newSigSet);
    sigaddset(&newSigSet, SIGPIPE);
    sigprocmask(SIG_BLOCK, &newSigSet, NULL);

	audioSource = [[AudioSource alloc] init];
    if (audioSource == nil) {
        NSLog(@"Error initializing audioSource");
    }
    
	// Disable signals for broken pipe (they're handled during the send call)
	struct sigaction act;		
	if( sigaction(SIGPIPE, NULL, &act) == -1)
		perror("Couldn't find the old handler for SIGPIPE");
	else if (act.sa_handler == SIG_DFL) {
		act.sa_handler = SIG_IGN;
		if( sigaction(SIGPIPE, &act, NULL) == -1)
			perror("Could not ignore SIGPIPE");
	}
	
	[networkServer openWithPort: 12345];
	[networkServer setDelegate: self];
	[networkServer acceptInBackground];
}

#pragma mark -
#pragma mark NetworkServer Delegate Methods
- (void)newNetworkSession:(NetworkSession *)newSession
{
    NSLog(@"Controller accepted new session.");
    
    // If this is the first network session,
    // we need to start the audio source
    if ([networkSessions count] == 0) {
        [audioSource startAudio];        
    }
    
    // Setup the new session
    [newSession setDelegate:self];
    [networkSessions addObject:newSession];
    
    // Notify the tableViewController of the new entry
//TODO: Notify the tableViewController of the new entry
}

#pragma mark -
#pragma mark NetworkSession Delegate Methods
- (void)sessionTerminated:(NetworkSession *)session
{
	[self disconnect:self];
}

#pragma mark -
#pragma mark User interface actions
- (IBAction)disconnect:(id)sender {
	NSLog(@"Recieved disconnect request.\n");
	
    // This is wrong
    NSInteger index = 0;
    
    // Find the index into the networkSessions array
    NetworkSession *disconnectSession = [networkSessions objectAtIndex:index];
    [disconnectSession retain];
    
    // Remove this session from the networkSessions array
    [networkSessions removeObjectAtIndex:index];
    
    // If the network sessions array is now empty stop processing audio
    if ([networkSessions count] == 0) {
        [audioSource stopAudio];
    }
    
    // Disconnect network and release
	[disconnectSession disconnect];
    [disconnectSession release];
    
    // Notify the tableViewController of the change	
}

- (IBAction)startServer:(id)sender {
    // Disable audio configurations
    [source     setEnabled:NO];
    [bitDepth   setEnabled:NO];
    [sampleRate setEnabled:NO];
    [channels   setEnabled:NO];
    
    // Change the label of the button
    [startStopButton setTitle:@"Stop"];
}

- (IBAction)stopServer:(id)sender {
    // Reenable audio configurations
    [source     setEnabled:YES];
    [bitDepth   setEnabled:YES];
    [sampleRate setEnabled:YES];
    [channels   setEnabled:YES];
    
    // Change the label of the button
    [startStopButton setTitle:@"Start"];
}

- (IBAction)setAudioDevice:(id)sender {
	NSLog(@"Recieved change audio unit request.\n");    
}

@end
