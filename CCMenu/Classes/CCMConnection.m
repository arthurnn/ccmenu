
#import "CCMConnection.h"
#import "CCMServerStatusReader.h"
#import "CCMKeychainHelper.h"
#import <SecurityInterface/SFCertificateTrustPanel.h>
#import <SecurityInterface/SFCertificateView.h>

@implementation CCMConnection

@synthesize feedURL;
@synthesize credential;
@synthesize delegate;

- (id)initWithFeedURL:(NSURL *)theFeedURL
{
    self = [super init];
    feedURL = [theFeedURL copy];
    return self;
}

- (id)initWithURLString:(NSString *)theFeedURL
{
    return [self initWithFeedURL:[NSURL URLWithString:theFeedURL]];
}

- (void)dealloc
{
    [feedURL release];
    [credential release];
    [receivedData release];
    [receivedResponse release];
    [nsurlConnection release]; // just in case
    [super dealloc];
}

- (BOOL)setUpCredential
{
    NSString *user = [feedURL user];
    if(user == nil)
        return NO;
    NSString *password = [CCMKeychainHelper passwordForURL:feedURL error:NULL];
    if(password == nil)
        return NO;
    [self setCredential:[NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceForSession]];
    return YES;
}


- (void)setUpForNewRequest
{
    [receivedData release];
    receivedData = [[NSMutableData alloc] init];
    [receivedResponse release];
    receivedResponse = nil;
}

- (void)cleanUpAfterRequest
{
	[nsurlConnection release];
	nsurlConnection = nil;
}


- (void)requestServerStatus
{
    if(nsurlConnection != nil)
        return;
    [self setUpForNewRequest];
    NSURLRequest *request = [NSURLRequest requestWithURL:feedURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    nsurlConnection = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
}

- (void)cancelRequest
{
	if(nsurlConnection == nil)
		return;
	[nsurlConnection cancel];
    [self cleanUpAfterRequest];
}


- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    NSString *m = [protectionSpace authenticationMethod];
    return ([m isEqualToString:NSURLAuthenticationMethodHTTPBasic]
            || [m isEqualToString:NSURLAuthenticationMethodHTTPDigest]
            || [m isEqualToString:NSURLAuthenticationMethodServerTrust]);
}


- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        SecTrustResultType result;
        SecTrustEvaluate([[challenge protectionSpace] serverTrust], &result);
        BOOL shouldGoAhead;
        switch(result)
        {
            case kSecTrustResultUnspecified:
            case kSecTrustResultProceed:
                shouldGoAhead = YES;
                break;
            case kSecTrustResultConfirm:
            case kSecTrustResultRecoverableTrustFailure:
            {
                SFCertificateTrustPanel *panel = [SFCertificateTrustPanel sharedCertificateTrustPanel];
                NSString *msg = [NSString stringWithFormat:@"CCMenu can't verify the identity of the server %@.", [feedURL host]];
                [panel setInformativeText:@"The certificate for this server is invalid. Do you want to continue anyway?"];
                [panel setAlternateButtonTitle:@"Cancel"];
                shouldGoAhead = ([panel runModalForTrust:[[challenge protectionSpace] serverTrust] message:msg] == NSOKButton);
                break;
            }
            default:
                shouldGoAhead = NO;
                break;
        }
        if(shouldGoAhead)
        {
            NSURLCredential *serverTrustCredential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            [[challenge sender] useCredential:serverTrustCredential forAuthenticationChallenge:challenge];
        }
        else
        {
            [[challenge sender] rejectProtectionSpaceAndContinueWithChallenge:challenge];
        }
    }
    else // basic and digest are the only others we accept
    {
        if(([challenge previousFailureCount] == 0) && ((credential != nil) || [self setUpCredential]))
            [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
        else
            [[challenge sender] cancelAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    receivedResponse = (NSHTTPURLResponse *)[response retain];
    // doc says this could be called multiple times, so we reset data
    [receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	CCMServerStatusReader *reader = [[[CCMServerStatusReader alloc] initWithServerResponse:receivedData] autorelease];
    [self cleanUpAfterRequest];
    NSError *error = nil;
    NSArray *infos = [reader readProjectInfos:&error];
    if(infos != nil)
        [delegate connection:self didReceiveServerStatus:infos];
    else
        [delegate connection:self hadTemporaryError:[self errorStringForParseError:error]];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self cleanUpAfterRequest];
	[delegate connection:self hadTemporaryError:[self errorStringForError:error]];
}


- (NSString *)errorStringForError:(NSError *)error
{
    NSString *description = [error localizedDescription];
    if([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserCancelledAuthentication))
    {
        description = @"Server requires authentication and there is a problem with the credentials. Please verify the connection details for the project.";
    }
    return [NSString stringWithFormat:@"Failed to get status from %@: %@",
             [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey],
             description];
}

- (NSString *)errorStringForResponse:(NSHTTPURLResponse *)response
{
    return [NSString stringWithFormat:@"Failed to get status from %@: %@",
             [response URL],
             [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]]];
}

- (NSString *)errorStringForParseError:(NSError *)error
{
    return [NSString stringWithFormat:@"Failed to parse status from %@: %@ (Maybe the server is returning a temporary HTML error page instead of an XML document.)",
             [feedURL description],
             [[error localizedDescription] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}

@end
