//
//  ViewController.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import "ViewController.h"
#import "AudioSource.h"
//#import "CoreAudio.h"

@implementation ViewController
- (id)initWithCoder:(NSCoder *)coder {
	
	self = [super initWithCoder:coder];
	
	if( self != nil ) {
		NSLog(@"Initializing View Controller.\n", coder);
		
		networkSession = nil;
	}
	
	return self;
}

- (void)awakeFromNib {
	[NSApp setDelegate:self];
}

- (IBAction)disconnect:(id)sender {
	NSLog(@"Recieved disconnect request.\n");
	
    // Stop processing audio
	[audioSource stopAudio];
    
    // Disconnect network and release
	[networkSession disconnect];
    [networkSession release];
	networkSession = nil;
    
    // Ensure that checkbox is correct
	[hostname setStringValue:@"Disconnected"];
	[connected setState:NSOffState];
	[connected setEnabled:false];
	
    // Re-enable audio source selector
	[source setEnabled:YES];
}

- (IBAction)setAudioDevice:(id)sender {
	NSLog(@"Recieved change audio unit request.\n");    
}

#pragma mark -
#pragma mark NSApp Delegate Methods
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSLog(@"Application finished launching");
    
	[audioSource init];
    
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
- (void)newNetworkSession: (NetworkSession *)newSession
{
	NSLog(@"Controller accepted new session.");
	
	networkSession = newSession;
    [networkSession retain];
	[networkSession setDelegate:self];
	
	// Set UI attributes
	[hostname setStringValue:[networkSession hostname]];
	[connected setState:NSOnState];
	[connected setEnabled:true];
	
	// Disable audio source selector
	[source setEnabled:NO];
    
	// Start processing audio
	[audioSource setSession:networkSession];
	[audioSource startAudio];
}

#pragma mark -
#pragma mark NetworkSession Delegate Methods
- (void)sessionTerminated:(NetworkSession *)session
{
	[self disconnect:self];
}

@end
