//
//  ViewController.h
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NetworkServer.h"
#import "AudioSource.h"

@interface ViewController : NSViewController <NetworkSessionDelegate> {	
	IBOutlet NetworkServer *networkServer;
	IBOutlet AudioSource   *audioSource;
    
	IBOutlet NSTextField   *hostname;
	IBOutlet NSButton	   *connected;
	IBOutlet NSComboBox	   *source;
	
	NetworkSession *networkSession;
}

- (IBAction)disconnect:(id)sender;
- (IBAction)setAudioDevice:(id)sender;

- (void)newNetworkSession:(NetworkSession *)session;
- (void)sessionTerminated:(NetworkSession *)session;

@end
