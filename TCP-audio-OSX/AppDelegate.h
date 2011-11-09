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

@interface AppDelegate : NSObject <NSApplicationDelegate,
                                   NSComboBoxDataSource>
{    
    IBOutlet NSComboBox     *source;
//  IBOutlet NSComboBox     *bitDepth;   // not used, assume highest
    IBOutlet NSComboBox     *sampleRate;
    IBOutlet NSTextField    *channels;
    IBOutlet NSButton       *startStopButton;
    
    IBOutlet NSArrayController *networkSessions;
    NetworkServer   *networkServer;
    AudioSource     *audioSource;
    
//  NSMutableArray  *networkSessions;
}

@property (assign) IBOutlet NSWindow *window;

// UI Actions
- (IBAction)disconnect:(id)sender;
- (IBAction)setAudioDevice:(id)sender;
- (IBAction)startServer:(id)sender;

// Network events
- (void)newNetworkSession:(NetworkSession *)session;
- (void)sessionTerminated:(NetworkSession *)session;

// Audio source events
- (void)audioData:(void *)data size:(NSUInteger)size;

// Combo box data source methods
// These are shared across all the combo boxes (select using aComboBox)
- (NSString *)comboBox:(NSComboBox *)aComboBox completedString:(NSString *)string;
- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)string;
- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index;
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox;


@end
