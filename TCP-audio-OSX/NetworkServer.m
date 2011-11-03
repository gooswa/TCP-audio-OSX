//
//  NetworkServer.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011 Oregon State University (COAS). All rights reserved.
//

#import "NetworkServer.h"
#import "ViewController.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include <unistd.h>
#include <netdb.h>
#include <signal.h>
#include <stdio.h>

int
ignoreSigpipe()
{
	sigset_t newSigSet;
	
	sigemptyset(&newSigSet);
	sigaddset(&newSigSet, SIGPIPE);
	return sigprocmask(SIG_BLOCK, &newSigSet, NULL);
}

@implementation NetworkServer

- (id)init {
	if( init != 0xdeadbeef ) {
		return self;
	}
	
	self = [super init];
	
	if( self != nil ) {
		NSLog(@"Initializing NetworkServer.\n");
		
		init	= true;
		error	= true;
		started = false;
        
		if(ignoreSigpipe() != 0) {
			NSLog(@"Error changing signal mask (SIGPIPE).");
			return self;
		}
        
	} else {
		NSLog(@"Error initializing NetworkServer class.\n");
	}
    
	error = false;
    
	return self;
}

- (bool)openWithPort: (int)inPort {	
	struct sockaddr_in server;
    
	NSLog(@"Starting NetworkServer.\n");
    
	port = inPort;
    
	if( (sock = socket(AF_INET, SOCK_STREAM, 0)) < 0 ) {
		NSLog(@"Error creating socket");
		error = true;
		return false;
	}
	
	server.sin_family = AF_INET;
	server.sin_addr.s_addr = INADDR_ANY;
	server.sin_port = htons( (short)port );
	
	if( bind(  sock, (struct sockaddr*)&server, sizeof(server)) < 0 ) {
		NSLog(@"Error binding to port");
		error = true;
		return false;
	}
	
	if( listen(sock, SOMAXCONN) < 0 ) {
		NSLog(@"Error listening for connections.");
		error = true;
		return false;			
	}
	
	error	= false;
	started = true;
    
	NSLog(@"Started Network Server on port %d.\n", port);
	
	return true;	
}

- (void)acceptLoop
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
	NetworkSession *networkSession = nil;
    
	// Listen for an incoming connection indefinitely 
	while( true ) {
		
		networkSession = [self accept];
		
		if( networkSession != nil ) {
			[delegate newNetworkSession: networkSession];			
		} else {
			NSLog(@"Error listening, retrying.");
		}
		
		[networkSession release];
	}
    
	[pool release];
}

- (void)acceptInBackground
{
	NSLog(@"Starting network listener thread.\n");
	[self performSelectorInBackground:@selector(acceptLoop) withObject:nil];
}

- (NetworkSession *)accept
{
	NetworkSession *networkSession = nil;
	NSString *hostnameString;
	
	struct sockaddr_in net_client;
	socklen_t len = sizeof(struct sockaddr_in);
	net_client.sin_addr.s_addr = INADDR_ANY;	// Allow connection from any client
	NSLog(@"Listening for Connection.");	
    
	// Listen for a connection (loop if interrupted)
	while( ((fileDescriptor = accept(sock, (struct sockaddr*)(&net_client), &len )) == -1) &&
		  (errno == EINTR) )
	{
		NSLog(@"Interrupted, resuming wait.");
	}
	
	// If the listen was successful create a session object	
	if( fileDescriptor != -1 ) {		
		
		networkSession = [[NetworkSession alloc] initWithSocket:sock andDescriptor:fileDescriptor];
		
		struct hostent *hostptr = gethostbyaddr((char*)&(net_client.sin_addr.s_addr), len, AF_INET);
		if( hostptr != nil ) {
			hostnameString = [[NSString alloc] initWithCString:(*hostptr).h_name];
		} else {
			hostnameString = [[NSString alloc] initWithString:@"Unknown Client."];
		}
		NSLog(@"New connection successful, to %@ (fd: %d).", hostnameString, fileDescriptor);
		
		[networkSession setHostname: hostnameString];
		[hostnameString release];
		
	} else {
		NSLog(@"Connection attempt failed.");
		error = true;
		return nil;
	}		
	
    //	[networkSession release];
	return networkSession;
}

- (void)close
{
	sock = fileDescriptor = -1;
	// WE NEED MORE HERE!
}

- (bool)started
{
	return started;
}

- (bool)error
{
	return error;
}

- (int)port
{
	return port;
}

- (id)delegate;
{
	return delegate;
}

- (void)setDelegate: (id)del
{
	delegate = del;
}

- (bool)setPort
{
	NSLog(@"Setting port not yet available.");
	
	return false;
}

@end
