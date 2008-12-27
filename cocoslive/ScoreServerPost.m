/* cocos2d for iPhone
 *
 * http://code.google.com/p/cocos2d-iphone
 *
 * Copyright (C) 2008 Ricardo Quesada
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the 'cocos2d for iPhone' license.
 *
 * You will find a copy of this license within the cocos2d for iPhone
 * distribution inside the "LICENSE" file.
 *
 */

#import "ScoreServer.h"

// free function used to sort
NSInteger alphabeticSort(id string1, id string2, void *reverse)
{
    if ((NSInteger *)reverse == NO)
        return [string2 localizedCaseInsensitiveCompare:string1];
    return [string1 localizedCaseInsensitiveCompare:string2];
}


@interface ScoreServer (Private)
-(void) addValue:(NSString*)value key:(NSString*)key;
-(void) calculateHashAndAddValue:(id)value key:(NSString*)key;
-(NSString*) getHashForData;
-(NSData*) getBodyValues;
-(NSString*) encodeData:(NSString*)data;
@end

@implementation ScoreServer
+(id) serverWithGameName:(NSString*) name gameKey:(NSString*) key delegate:(id) delegate
{
	return [[[self alloc] initWithGameName:name gameKey:key delegate:delegate] autorelease];
}

-(id) initWithGameName:(NSString*) name gameKey:(NSString*) key delegate:(id)aDelegate
{
	self = [super init];
	if( self ) {
		gameKey = [key retain];
		gameName = [name retain];
		bodyValues = [[NSMutableArray arrayWithCapacity:5] retain];
		delegate = [aDelegate retain];
		receivedData = [[NSMutableData data] retain];
	}
	
	return self;
}

-(void) dealloc
{
#if DEBUG
	NSLog( @"deallocing %@", self);
#endif
	[delegate release];
	[gameKey release];
	[gameName release];
	[bodyValues release];
	[receivedData release];
	[super dealloc];
}


#pragma mark ScoreServer send scores
-(BOOL) sendScore: (NSDictionary*) dict
{	
    [receivedData setLength:0];
		
	// create the request
	NSMutableURLRequest *post=[NSMutableURLRequest requestWithURL:[NSURL URLWithString: SCORE_SERVER_SEND_URL]
													cachePolicy:NSURLRequestUseProtocolCachePolicy
													timeoutInterval:10.0];
	
	[post setHTTPMethod: @"POST"];
	[post setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	
	CC_MD5_Init( &md5Ctx);

	// hash SHALL be calculated in certain order
	NSArray *keys = [dict allKeys];
	int reverseSort = NO;
	NSArray *sortedKeys = [keys sortedArrayUsingFunction:alphabeticSort context:&reverseSort];
	for( id key in sortedKeys )
		[self calculateHashAndAddValue:[dict objectForKey:key] key:key];

	// device id is hashed to prevent spoofing this same score from different devices
	// one way to prevent a replay attack is to send cc_id & cc_time and use it as primary keys

	
	[self addValue:[[UIDevice currentDevice] uniqueIdentifier] key:@"cc_id"];
	[self addValue:gameName key:@"cc_gamename"];
	[self addValue:[self getHashForData] key:@"cc_hash"];
	[self addValue:SCORE_SERVER_PROTOCOL_VERSION key:@"cc_prot_ver"];

	[post setHTTPBody: [self getBodyValues] ];
	
	// create the connection with the request
	// and start loading the data
	NSURLConnection *theConnection=[[NSURLConnection alloc] initWithRequest:post delegate:self];
	
	if ( ! theConnection)
		return NO;
	
	return YES;
}

-(void) calculateHashAndAddValue:(id) value key:(NSString*) key
{
	NSString *val;
	// value shall be a string or nsnumber
	if( [value respondsToSelector:@selector(stringValue)] )
		val = [value stringValue];
	else if( [value isKindOfClass:[NSString class]] )
		val = value;
	else
		[NSException raise:@"Invalid format for value" format:@"Invalid format for value. addValue"];

	[self addValue:val key:key];
	
	const char * data = [val UTF8String];
	CC_MD5_Update( &md5Ctx, data, strlen(data) );
}

-(void) addValue:(NSString*)value key:(NSString*) key
{

	NSString *encodedValue = [self encodeData:value];
	NSString *encodedKey = [self encodeData:key];
		
	[bodyValues addObject: [NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue] ];
}

-(NSData*) getBodyValues {
	NSMutableData *data = [[NSMutableData alloc] init];
	
	BOOL first=YES;
	for( NSString *s in bodyValues ) {
		if( !first)
			[data appendBytes:"&" length:1];
		
		[data appendBytes:[s UTF8String] length:[s length]];
		first = NO;
	}
	
	return [data autorelease];
}

-(NSString*) getHashForData
{
	NSString *ret;
	unsigned char  pTempKey[16];
	
	// update the hash with the secret key
	const char *data = [gameKey UTF8String];
	CC_MD5_Update(&md5Ctx, data, strlen(data));
	
	// then get the hash
	CC_MD5_Final( pTempKey, &md5Ctx);

//	NSData *nsdata = [NSData dataWithBytes:pTempKey length:16];
	ret = [NSString stringWithString:@""];
	for( int i=0;i<16;i++) {
		ret = [NSString stringWithFormat:@"%@%02x", ret, pTempKey[i] ];
	}

	return ret;
}

-(NSString*) encodeData:(NSString*) data
{
	NSString *newData;
	
	newData = [data stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

	// '&' and '=' should be encoded manually
	newData = [newData stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
	newData = [newData stringByReplacingOccurrencesOfString:@"=" withString:@"%3D"];

	return newData;
}

#pragma mark NSURLConnection Delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    // this method is called when the server has determined that it
    // has enough information to create the NSURLResponse
	
    // it can be called multiple times, for example in the case of a
    // redirect, so each time we reset the data.
    // receivedData is declared as a method instance elsewhere
    [receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // append the new data to the receivedData
    // receivedData is declared as a method instance elsewhere
	[receivedData appendData:data];
	
	NSString *dataString = [NSString stringWithCString:[data bytes] length: [data length]];
	NSLog( @"data: %@", dataString);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    // release the connection, and the data object
    [connection release];
	
	if( [delegate respondsToSelector:@selector(scoreRequestFail:) ] )
		[delegate scoreRequestFail:self];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{		
    [connection release];
	
	if( [delegate respondsToSelector:@selector(scoreRequestOk:) ] )
		[delegate scoreRequestOk:self];
}

-(NSURLRequest *)connection:(NSURLConnection *)connection
			willSendRequest:(NSURLRequest *)request
           redirectResponse:(NSURLResponse *)redirectResponse
{
    NSURLRequest *newRequest=request;
    if (redirectResponse) {
        newRequest=nil;
    }
	
    return newRequest;
}

@end