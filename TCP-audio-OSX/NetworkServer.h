//
//  NetworkServer.h
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NetworkSession.h"

@interface NetworkServer : NSObject {
    
	bool init;
	bool started;
	bool error;
	
	int port;
    
	int	sock;
	int fileDescriptor;
    
	id delegate;
}

- (id)init;

// Start/stop server from listening
- (bool)openWithPort: (int)port;
- (void)close;

// Getters/Setters
- (bool)started;
- (bool)error;
- (int)port;
- (id)delegate;

- (void)setDelegate: (id)delegate;

// Methods to accept a connection (
- (NetworkSession *)accept;
- (void)acceptInBackground;

@end
