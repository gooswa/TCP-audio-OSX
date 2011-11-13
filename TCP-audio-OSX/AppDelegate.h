//
//  AppDelegate.h
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NetworkSession.h"
#import "NetworkServer.h"
#import "AudioSource.h"

#define NETWORK_PORT 12345

@interface AudioSendOperation : NSOperation {
@private
    NSDictionary *session;
    NSData      *data;
    id          notify;
    SEL         selector;
}

- (id)initWithSession:(NSDictionary *)sessionDict
              andData:(NSData *)data
        onErrorNotify:(id)sender
         withSelector:(SEL)selector;
    
@end

@interface AppDelegate : NSObject //<NSApplicationDelegate,
                                   //NSComboBoxDataSource,
                                   //NSTableViewDataSource,
                                   //NSTableViewDelegate>
{
	IBOutlet NSWindow			*window;
    IBOutlet NSComboBox         *source;
    IBOutlet NSComboBox         *sampleRate;
    IBOutlet NSComboBox         *channels;
    IBOutlet NSButton           *startStopButton;
    IBOutlet NSTableView        *tableView;
    IBOutlet NSProgressIndicator *progressIndicator;
    
    NSMutableArray              *networkSessions;
    NSMutableArray              *sessionOperationQueues;
    NetworkServer               *networkServer;
    AudioSource                 *audioSource;
    
}

@property (assign) IBOutlet NSWindow *window;

// UI Actions
- (IBAction)disconnectPressed:(id)sender;
- (IBAction)setAudioDevice:(id)sender;
- (IBAction)toggleServer:(id)sender;

// Network events
- (void)newNetworkSession:(NetworkSession *)session;
- (void)sessionTerminated:(NetworkSession *)session;

// Audio source events
- (void)audioData:(NSData *)data;

@end
