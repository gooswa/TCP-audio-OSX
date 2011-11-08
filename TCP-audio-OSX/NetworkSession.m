//
//  NetworkSession.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import "NetworkSession.h"

@implementation NetworkSession

- (id)initWithHost:(NSString*)hostName Port:(int)port
{
	self = [super init];
	
	if( self != nil ) {		
		hp = gethostbyname( [hostName UTF8String] );
		if( hp == nil ) {
			perror( "Looking up host address" );
			goto error;
		}
		
		sock = socket( AF_INET, SOCK_STREAM, 0 );
		if( sock == -1 ) {
			perror( "Opening Socket" );
			goto error;
		}
		
		memcpy((char *)&server.sin_addr, hp->h_addr_list[0], hp->h_length);
		server.sin_port = htons((short)port);
		server.sin_family = AF_INET;
        
		written = read =  0;
		fileDescriptor = -1;		
	} 
    
	return self;
	
error:
	perror("Creating socket for Network Session");
	self = nil;
	return self;
}

- (id)initWithSocket:(int)socket andDescriptor:(int)fd
{
	self = [super init];
	
	if( self != nil ) {		
		written = read =  0;
		sock = socket;
		fileDescriptor = fd;
		connected = true;
	}
	
	return self;
	
error:
	perror("Creating socket for Network Session");
	self = nil;
	return self;	
}

- (bool)connect
{
	int retval;
	
	while( ((retval = connect( sock, (struct sockaddr *)&server, sizeof(server))) == -1)
          && (errno == EINTR) )
		;
	
	if( retval == -1 ) {
		perror("Unable to connect");
		connected = NO;
	} else {
		
		// When the remote connection is closed, we DO NOT want a SIGPIPE: ask for a EPIPE instead.
		int opt_yes = 1;
		setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt_yes, sizeof(opt_yes));
		
		connected = YES;
		fileDescriptor = sock;
	}
    
	return connected;
}

- (void)disconnect
{
	close(fileDescriptor);
	sock = -1;
	fileDescriptor = -1;
	connected = NO;
}

- (bool)sendData:(NSData*)theData
{
	size_t retval;
	size_t localWritten = 0;
	uint32_t dataLength;
    
    if ([theData length] > UINT32_MAX) {
        NSLog(@"Contents of \"theData\" larger than what can fit in 32 bits!");
        exit(EXIT_FAILURE);
    }
    
    dataLength = (uint32_t)[theData length];
	
	if( !connected ) {
		if( ![self connect] ) {
			perror("Unable to send, not connected and unable to connect");
			return NO;
		}
	}
	
	do {
		dataLength = htonl( dataLength );
		retval = send(fileDescriptor, &dataLength, sizeof(uint32_t), 0);
		if( retval == -1 ) {
			perror("Writing bytes to the network");
			return NO;
		}
		
		retval = send(fileDescriptor, [theData bytes], [theData length], 0);
		if( retval == -1 ) {
			perror("Writing bytes to the network");
			return NO;
		}
		
		localWritten += retval + sizeof(int);
		
	} while( localWritten == [theData length] );
	
	written += localWritten;
	
	return YES;
}

- (size_t)send:(int)length bytes:(void *)data
{
	if( !connected ) {
		if( ![self connect] ) {
			perror("Unable to send, not connected and unable to connect");
			return NO;
		}
	}
	
	ssize_t retval;
    retval = send( fileDescriptor, data, length, 0 );
    if( retval < 0 ) {
		perror("Writing data");
		if( errno == EPIPE ) {
			[delegate sessionTerminated:self];
		}
	}
	
	return retval;
}

- (NSData*)getData
{
	if( !connected ) {
		if( ![self connect] ) {
			perror("Unable to receive, not connected and unable to connect");
			return nil;
		}
	}	
	
	return nil;
}

- (size_t)bytesWritten
{
	return written;
}

- (size_t)bytesRead
{
	return read;
}

- (NSString *)hostname
{
	NSString *retval = [hostname copy];
    [retval autorelease];
    
    return retval;
}

- (void)setHostname:(NSString *)newHostname
{
	hostname = newHostname;
}

- (void)setDelegate:(id)del
{
	delegate = del;
}

@end
