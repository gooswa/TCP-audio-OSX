//
//  AppDelegate.m
//  TCP-audio-OSX
//
//  Created by William Dillon on 11/3/11.
//  Copyright (c) 2011. All rights reserved.
//

#import "AppDelegate.h"

NSString *sessionNetworkKey = @"sessionNetwork";
NSString *sessionOperationQueueKey = @"sessionOperationQueue";

@implementation AudioSendOperation

- (id)initWithSession:(NSDictionary *)sessionDict
              andData:(NSData *)inData
        onErrorNotify:(id)inSender
         withSelector:(SEL)inSelector
{
    self = [super init];
    
    if (self == nil) {
        NSLog(@"Unable to create AudioSendOperation.");
        return self;
    }
    
    session     = [sessionDict retain];
    data        = [inData retain];
    selector    = inSelector;
    notify      = inSender;
    
    return self;
}

- (void)main
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    bool success = NO;
    
    success = [[session objectForKey:sessionNetworkKey] sendData:data];
    
    if (!success) {
        [notify performSelectorOnMainThread:selector
                                 withObject:session
                              waitUntilDone:NO];
    }
    
    [session release];
    [data release];
    
    [pool drain];
}

@end

@implementation AppDelegate

@synthesize window = _window;

#pragma mark -
#pragma mark NSApp Delegate Methods
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSLog(@"Application finished launching");
    
	audioSource = [[AudioSource alloc] init];
    if (audioSource == nil) {
        NSLog(@"Error initializing audioSource");
        exit(EXIT_FAILURE);
    }
    
    [audioSource setDelegate:self];
    
    // Setup the comboboxes
    [source setUsesDataSource:YES];
    [source setDataSource:self];
    [sampleRate setUsesDataSource:YES];
    [sampleRate setDataSource:self];
    [channels setUsesDataSource:YES];
    [channels setDataSource:self];
    [source selectItemAtIndex:0];   // Defalt to the first device
    [source reloadData];

	// Disable signals for broken pipe (they're handled during the send call)
    // I think I'm doing this 2 different ways.  Probably can remove one.
    sigset_t newSigSet;
    sigemptyset(&newSigSet);
    sigaddset(&newSigSet, SIGPIPE);
    sigprocmask(SIG_BLOCK, &newSigSet, NULL);
    
    struct sigaction act;		
	if( sigaction(SIGPIPE, NULL, &act) == -1)
		perror("Couldn't find the old handler for SIGPIPE");
	else if (act.sa_handler == SIG_DFL) {
		act.sa_handler = SIG_IGN;
		if( sigaction(SIGPIPE, &act, NULL) == -1)
			perror("Could not ignore SIGPIPE");
	}

    networkSessions = [[NSMutableArray alloc] init];
    
    // Create the network server
	networkServer = [[NetworkServer alloc] init];
    [networkServer setDelegate:self];
    
    [self setAudioDevice:self];
}

#pragma mark -
#pragma mark NetworkServer Delegate Methods
- (void)newNetworkSession:(NetworkSession *)newSession
{
    NSLog(@"Controller accepted new session.");
    
    // If this is the first network session,
    // we need to start the audio source
    if (![audioSource running]) {
        [audioSource startAudio];
        [progressIndicator startAnimation:self];
    }
    
    // Setup the new session
    [newSession setDelegate:self];
    
    // Setup an operation queue (serially)
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue setMaxConcurrentOperationCount:1];
    
    // Create a dictionary for this session
    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                          newSession, sessionNetworkKey,
                          queue, sessionOperationQueueKey , nil];
    
    [networkSessions addObject:dict];
    [dict release];
    [queue release];
    
    // Notify the tableViewController of the new entry
    [tableView reloadData];
}

#pragma mark -
#pragma mark NetworkSession Delegate Methods
- (void)sessionTerminated:(NetworkSession *)session
{
    NSDictionary *dict = nil;
    
    // Locate the dict matching this session in the array
    for (NSDictionary *sessionDict in networkSessions) {
        if ([sessionDict objectForKey:sessionNetworkKey] == session) {
            dict = sessionDict;
        }
    }
    
    if (dict == nil) {
        NSLog(@"Unable to find dictionary matching session with %@", [session hostname]);
        return;
    }
    
    // Clean out the operation queue
    [[dict objectForKey:sessionOperationQueueKey] cancelAllOperations];

    // Release resources
    [networkSessions removeObject:session];
    
    if ([networkSessions count] == 0) {
        [audioSource stopAudio];
        [progressIndicator stopAnimation:self];
    }
    
    // Reload the sessions table view
    [tableView reloadData];    
}

#pragma mark -
#pragma mark Other network and audioSourceDelegate methods
- (void)sendData:(NSData *)data
              to:(NSDictionary *)sessionDict
{
    NetworkSession *session;
    session = [sessionDict objectForKey:sessionOperationQueueKey];
        
    if ([session sendData:data] == NO) {
        // If there was an error print a message
        NSLog(@"Problem sending data to %@, disconnecting client.",
              [[sessionDict objectForKey:sessionNetworkKey] hostname]);

        // Then disonnect the host (on the main thread)
        [self performSelectorOnMainThread:@selector(disconnect:)
                               withObject:sessionDict
                            waitUntilDone:NO];
    }
}

- (void)audioBytes:(void *)bytes size:(NSUInteger)size
{
    // The audio data should be 32-bit floats with the channels interleaved.
    // This is the format we want to send on the network, which means that we
    // can just dump the bytes onto the sockets.  However, because the write
    // operation can block if the channel to the remote host isn't capable of
    // maintaining the data rate.  Therefore, we need send it asynchronously
    // and have a mechanisim to drop audio frames if it comes to that.
    
    // Create an NSData to be used in the operations
    // This copies the bytes, becuase the caller needs to reuse the buffer.
    NSData *data = [[NSData alloc] initWithBytes:bytes
                                          length:size];
    
    for (NSDictionary *session in networkSessions) {
        NSOperationQueue *queue;
        queue = [session objectForKey:sessionOperationQueueKey];
        
        // Only enqueue this new block of data if the remote side is keeping up
        if ([queue operationCount] < 10) {
            AudioSendOperation *op;
            op = [[AudioSendOperation alloc] initWithSession:session
                                                     andData:data
                                               onErrorNotify:self
                                                withSelector:@selector(disconnect:)];
            
            [queue addOperation:op];
            [op release];   
        }
    }
    
    [data release];
    
    return;
}

- (void)disconnect:(NSDictionary *)sessionDict
{
    NetworkSession *disconnectSession;
    NSOperationQueue *disconnectQueue;
    
    disconnectSession = [sessionDict objectForKey:sessionNetworkKey];
    disconnectQueue = [sessionDict objectForKey:sessionOperationQueueKey];
    
    // Cancel all operations on this host's operation queue
    [disconnectQueue cancelAllOperations];
    [disconnectSession disconnect];
    
    // Remove this session from the networkSessions array
    [networkSessions removeObject:sessionDict];
    
    // If the network sessions array is now empty stop processing audio
    if ([networkSessions count] == 0) {
        [audioSource stopAudio];
        [progressIndicator stopAnimation:self];
    }
    
    [tableView reloadData];
}


#pragma mark -
#pragma mark User interface actions
- (IBAction)disconnectPressed:(id)sender {
	NSLog(@"Recieved disconnect request.\n");
	
    NSInteger index = [tableView selectedRow];
    
    // Find the index into the networkSessions array
    NSDictionary *dict = [networkSessions objectAtIndex:index];
    [self disconnect:dict];
    
    // Reload the tableview data
    [tableView reloadData];
}

- (IBAction)toggleServer:(id)sender {
    if (![networkServer started]) {
        // Change the label of the button
        [startStopButton setTitle:@"Stop"];
        
        // Open the server port
        [networkServer openWithPort:NETWORK_PORT];
        
        // Begin processing new connections
        [networkServer acceptInBackground];

        if ([networkServer started] == NO) {
            return;
        }
        
        // Disable audio configurations
        [source     setEnabled:NO];
        [sampleRate setEnabled:NO];
        [channels   setEnabled:NO];
        
        // Set the audio settings in the audioSource
        int device = (int)[source indexOfSelectedItem];
        float rate = [sampleRate floatValue];
        int chans  = (int)[channels integerValue];
        [audioSource setDevice:device];
        [audioSource setSampleRate:rate];
        [audioSource setChannels:chans];
        
    } else {
        // Shutdown the server
        [networkServer close];
        
        // Close all current connections
        while ([networkSessions count] > 0) {
            NSDictionary *session = [networkSessions objectAtIndex:0];
            [self disconnect:session];
        };

        // Update the tableview
        [tableView reloadData];
        
        // Stop the audio
        [audioSource stopAudio];
        [progressIndicator stopAnimation:self];

        // Re-enable audio configurations
        [source     setEnabled:YES];
        [sampleRate setEnabled:YES];
        [channels   setEnabled:YES];
        
        // Change the label of the button
        [startStopButton setTitle:@"Start"];
    }
}

- (IBAction)setAudioDevice:(id)sender {
    if ([source indexOfSelectedItem] < 0) {
        return;
    }
    
    // Reload the data for the other comboboxes
    [sampleRate reloadData];
    [channels reloadData];
    
    // Select the correct sample rate for the nominal rate
    NSArray *devices = [audioSource devices];
    NSDictionary *device = [devices objectAtIndex:[source indexOfSelectedItem]];
    NSUInteger currentSampleRate;
    currentSampleRate = [[device objectForKey:audioSourceNominalSampleRateKey]
                         intValue];
    NSArray *rates = [device objectForKey:audioSourceAvailableSampleRatesKey];
    for (int i = 0; i < [rates count]; i++) {
        NSRange sampleRateRange;
        sampleRateRange = [[rates objectAtIndex:i] rangeValue];
        if (currentSampleRate >= sampleRateRange.location &&
            currentSampleRate <= sampleRateRange.location + 
                                 sampleRateRange.length) {
            [sampleRate selectItemAtIndex:i];
        }
    }
    
    // Default to 2 channels
    [channels selectItemAtIndex:1];
}

#pragma mark -
#pragma mark Tableview data source methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [networkSessions count];
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info 
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    return NO;
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row
{
    NSString *columnIdentifier = [tableColumn identifier];
    NSDictionary *dict = [networkSessions objectAtIndex:row];
    
    // Only the hostname column has content
    if ([columnIdentifier isEqualToString:@"hostname"]) {
        NSString *hostname = [[dict objectForKey:sessionNetworkKey] hostname];
        return hostname;
    }

    return nil;

}

- (BOOL)tableView:(NSTableView *)tableView
        writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard
{
    return NO;
}

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard
{
    return NO;
}

#pragma mark -
#pragma mark Combo box data source methods

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
    if (aComboBox == source) {
        NSArray *audioDevices = [audioSource devices];
        return [audioDevices count];
    }
    
    if (aComboBox == sampleRate) {
        if ([source indexOfSelectedItem] < 0) {
            return 0;
        }
        
        // Get the selected device
        NSDictionary *device;
        device = [[audioSource devices] objectAtIndex:[source indexOfSelectedItem]];
        
        return [[device objectForKey:audioSourceAvailableSampleRatesKey] count];
    }

    if (aComboBox == channels) {
        if ([source indexOfSelectedItem] < 0) {
            return 0;
        }
        
        // Get the selected device
        NSDictionary *device;
        device = [[audioSource devices] objectAtIndex:[source indexOfSelectedItem]];
        
        // The number of channels
        return [[device objectForKey:audioSourceInputChannelsKey] intValue];
    }
    
    return 0;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
    if (aComboBox == source) {
        NSString *string = nil;
        
        // Search the audioDevices array for the object at given index
        NSArray *audioDevices = [audioSource devices];
        for (NSDictionary *device in audioDevices) {
            if ([[device objectForKey:audioSourceDeviceIDKey] intValue] == index) {
                string = [device objectForKey:audioSourceNameKey];
            }
        }
        
        return string;
    }
    
    if (aComboBox == sampleRate) {
        NSString *string;
        
        // Get the selected device
        if ([source indexOfSelectedItem] < 0) {
            return nil;
        }

        NSDictionary *device;
        device = [[audioSource devices] objectAtIndex:[source indexOfSelectedItem]];

        // Get the sample rate at given index
        NSArray *sampleRates = [device objectForKey:audioSourceAvailableSampleRatesKey];
        NSValue *sampleRateValue = [sampleRates objectAtIndex:index];
        NSRange sampleRateRange = [sampleRateValue rangeValue];
        string = [NSString stringWithFormat:@"%d", sampleRateRange.location];
        
        return string;
    }
    
    if (aComboBox == channels) {
        return [NSString stringWithFormat:@"%d", index + 1];
    }
    
    return nil;
}

@end
