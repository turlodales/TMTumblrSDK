//
//  TMURLSession.m
//  TMTumblrSDK
//
//  Created by Bryan Irace on 3/26/15.
//  Copyright (c) 2015 Tumblr. All rights reserved.
//
#import "TMOAuth.h"
#import "TMSDKFunctions.h"
#import "TMURLSession.h"
#import "TMAPIRequest.h"
#import "TMURLSessionObserver.h"
#import "TMURLEncoding.h"
#import "TMHTTPRequest.h"
#import "TMConcreteURLSessionTaskDelegate.h"

#import "TMRequestParamaterizer.h"
#import "TMRequestTransformer.h"
#import "TMRequestBody.h"
#import "TMMultiPartRequestBodyProtocol.h"
#import "TMMultipartEncodedForm.h"
#import "TMUploadSessionTaskCreator.h"

NSString * _Nonnull const TMURLSessionInvalidateApplicationCredentialsNotificationKey = @"TMURLSessionInvalidateApplicationCredentials";

NSString * _Nonnull const TMURLSessionInvalidateHTTPHeadersNotificationKey = @"TMURLSessionInvalidateHTTPHeaders";

@interface TMURLSession ()

@property (nonatomic, nonnull) NSURLSession *session;
@property (nonatomic, nullable) TMAPIApplicationCredentials *applicationCredentials;
@property (nonatomic, nullable) TMAPIUserCredentials *userCredentials;

@property (nonatomic, nullable, readonly) TMURLSessionObserver *observer;
@property (nullable, nonatomic, readonly) id <TMSessionTaskUpdateDelegate> sessionTaskUpdateDelegate;

@property (nonatomic, nonnull, readonly) TMConcreteURLSessionTaskDelegate *concreteURLSessionTaskDelegate;
@property (nonatomic, nullable, weak, readonly) id <NSURLSessionDataDelegate> customURLSessionDataDelegate;

@property (nonatomic, nullable, weak, readonly) id <TMNetworkActivityIndicatorManager> networkActivityManager;
@property (nonatomic, nullable, weak, readonly) id <TMURLSessionMetricsDelegate> sessionMetricsDelegate;
@property (nonatomic, nullable, weak, readonly) id <TMRequestTransformer> requestTransformer;

@property (nonatomic, nullable, readonly) NSDictionary *additionalHeaders;

@end

@implementation TMURLSession

@synthesize networkActivityVisibilityCounter = _networkActivityVisibilityCounter;

#pragma mark - Initialization

- (nonnull instancetype)initWithConfiguration:(nonnull NSURLSessionConfiguration *)configuration
                       applicationCredentials:(nullable TMAPIApplicationCredentials *)applicationCredentials
                              userCredentials:(nullable TMAPIUserCredentials *)userCredentials {
    return [self initWithConfiguration:configuration
                applicationCredentials:applicationCredentials
                       userCredentials:userCredentials
                networkActivityManager:nil
             sessionTaskUpdateDelegate:nil
                sessionMetricsDelegate:nil
                    requestTransformer:nil
          customURLSessionDataDelegate:nil
                     additionalHeaders:nil];
}

- (nonnull instancetype)initWithConfiguration:(nonnull NSURLSessionConfiguration *)configuration
                       applicationCredentials:(nullable TMAPIApplicationCredentials *)applicationCredentials
                              userCredentials:(nullable TMAPIUserCredentials *)userCredentials
                       networkActivityManager:(nullable id <TMNetworkActivityIndicatorManager>)networkActivityManager
                    sessionTaskUpdateDelegate:(nullable id <TMSessionTaskUpdateDelegate>)sessionTaskUpdateDelegate
                       sessionMetricsDelegate:(nullable id <TMURLSessionMetricsDelegate>)sessionMetricsDelegate
                           requestTransformer:(nullable id <TMRequestTransformer>)requestTransformer
                 customURLSessionDataDelegate:(nullable id <NSURLSessionDataDelegate>)customURLSessionDataDelegate
                            additionalHeaders:(nullable NSDictionary *)additionalHeaders {
    NSParameterAssert(configuration);

    self = [super init];
    if (self) {

        _additionalHeaders = [additionalHeaders copy];
        _sessionTaskUpdateDelegate = sessionTaskUpdateDelegate;
        _sessionMetricsDelegate = sessionMetricsDelegate;
        _requestTransformer = requestTransformer;
        _applicationCredentials = applicationCredentials;
        _userCredentials = userCredentials;
        _customURLSessionDataDelegate = customURLSessionDataDelegate;
        _concreteURLSessionTaskDelegate = [[TMConcreteURLSessionTaskDelegate alloc] initWithSessionMetricsDelegate:sessionMetricsDelegate];
        _networkActivityManager = networkActivityManager;
        
        _session = [self sessionWithConfiguration:configuration];

        _observer = [[TMURLSessionObserver alloc] initWithHandlers:^NSArray *() {
            NSMutableArray *handlers = [[NSMutableArray alloc] init];
            if (self->_networkActivityManager) {
                self->_networkActivityVisibilityCounter = [[TMNetworkActivityVisiblityCounter alloc] initWithNetworkActivityIndicatorManager:self->_networkActivityManager];
                
                typeof(self) __weak weakSelf = self;
                [handlers addObject:^void(TMURLSessionTaskState state, NSURLSessionTask *sessionTask) {
                    [weakSelf.networkActivityVisibilityCounter update:state];
                }];
                
            }
            
            if (sessionTaskUpdateDelegate) {
                typeof(self) __weak weakSelf = self;
                [handlers addObject:^void(TMURLSessionTaskState state, NSURLSessionTask *sessionTask) {
                    [weakSelf.sessionTaskUpdateDelegate URLSession:sessionTask updatedStatusTo:state];
                }];
            }
            
            return handlers;
            
        }()];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(invalidateApplicationCredentials:) name:TMURLSessionInvalidateApplicationCredentialsNotificationKey object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(invalidateHTTPHeaders:) name:TMURLSessionInvalidateHTTPHeadersNotificationKey object:nil];
    }
    
    return self;
}

#pragma mark - Invalidation

- (void)invalidateApplicationCredentials:(NSNotification *)notification {
    NSAssert([[notification object] isKindOfClass:[TMAPIUserCredentials class]] || ![notification object], @"Must be an instance of TMAPIUserCredentials");
    
    self.userCredentials = notification.object;
}

- (void)invalidateHTTPHeaders:(NSNotification *)notification {
    NSAssert([[notification object] isKindOfClass:[NSDictionary class]], @"Must be an instance of NSDictionary");
    
    NSURLSessionConfiguration *configuration = self.session.configuration;
    configuration.HTTPAdditionalHeaders = notification.object;
    self.session = [self sessionWithConfiguration:configuration];
}

#pragma mark - Validation

- (BOOL)canSignRequests {
    return self.userCredentials.validCredentials && self.applicationCredentials.validCredentials;
}

#pragma mark - TMURLSession

- (nonnull NSURLSessionTask *)dataTaskWithRequest:(nonnull id <TMRequest>)request
                                completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {
    NSParameterAssert(request);
    NSParameterAssert(completionHandler);

    NSURLSessionDataTask *sessionTask = [self sessionTaskWithURLRequest:[self paramaterizedRequestFromRequest:request] completionHandler:completionHandler];
    [self.observer addSessionTask:sessionTask];
    return sessionTask;
}

- (nonnull NSURLSessionTask *)dataTaskWithRequest:(nonnull id <TMRequest>)request
                               incrementalHandler:(nonnull TMURLSessionRequestIncrementedHandler)incrementalHandler
                                  progressHandler:(nonnull TMURLSessionRequestProgressHandler)progessHandler
                                completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {

    NSParameterAssert(request);
    NSParameterAssert(incrementalHandler);
    NSParameterAssert(completionHandler);

    NSURLSessionDataTask *sessionTask = [self sessionTaskWithURLRequest:[self paramaterizedRequestFromRequest:request]];
    [self.concreteURLSessionTaskDelegate addSessionTask:sessionTask
                                      completionHandler:completionHandler
                                     incrementalHandler:incrementalHandler
                                         progressHandler:progessHandler];

    [self.observer addSessionTask:sessionTask];
    return sessionTask;
}

- (nonnull NSURLSessionTask *)taskWithRequest:(nonnull id <TMRequest>)request
                           incrementalHandler:(nonnull TMURLSessionRequestIncrementedHandler)incrementalHandler
                              progressHandler:(nonnull TMURLSessionRequestProgressHandler)progressHandler
                            completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {
    NSParameterAssert(request);
    NSParameterAssert(incrementalHandler);
    NSParameterAssert(progressHandler);
    NSParameterAssert(completionHandler);

    id <TMRequest> transformedRequest = [self.requestTransformer transformRequest:request] ?: request;

    if (!request.isUpload) {
        return [self dataTaskWithRequest:transformedRequest incrementalHandler:incrementalHandler progressHandler:progressHandler completionHandler:completionHandler];
    }
    else {
        return [self uploadRequest:transformedRequest incrementalHandler:incrementalHandler progressHandler:progressHandler completionHandler:completionHandler];
    }
}

- (NSURLSessionTask *)taskWithRequest:(nonnull id <TMRequest>)request
                    completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {

    NSParameterAssert(request);
    NSParameterAssert(completionHandler);

    id <TMRequest> transformedRequest = [self.requestTransformer transformRequest:request] ?: request;

    if (!request.isUpload) {
        return [self dataTaskWithRequest:transformedRequest completionHandler:completionHandler];
    }
    else {
        return [self uploadRequest:transformedRequest incrementalHandler:nil progressHandler:nil completionHandler:completionHandler];
    }
}

- (NSURLSessionUploadTask *)backgroundUploadTaskWithRequest:(id <TMRequest>)request {
    NSParameterAssert(request);
    
    TMMultipartEncodedForm *form;
    // If the requestBody is of type TMMultiPartRequestBodyProtocol we should use `encodeWithError:` to be able to encode into a file in a memory efficient way.
    if ([request.requestBody conformsToProtocol:@protocol(TMMultiPartRequestBodyProtocol)]) {
        id<TMMultiPartRequestBodyProtocol> multiPartBody = (id<TMMultiPartRequestBodyProtocol>)request.requestBody;
        NSError *encodingError;
        form = [multiPartBody encodeWithError:&encodingError];
        if (encodingError || !form) {
            NSAssert(NO, @"Failed to encode multipart body request.");
            return nil;
        }
    }
    else {
        NSData *bodyData = [request.requestBody bodyData];
        form = [[TMMultipartEncodedForm alloc] initWithData:bodyData];
    }
    if (!form.fileURL) {
        NSAssert(NO, @"Background tasks must be encoded into a file.");
        return nil;
    }
    
    // For the background tasks we need to have the request encoded into a file.
    NSURLSessionUploadTask *task = [self.session uploadTaskWithRequest:[self paramaterizedRequestFromRequest:request]
                                                              fromFile:form.fileURL];
    return task;
}

- (nonnull NSURLSessionTask *)uploadRequest:(nonnull id <TMRequest>)request
                         incrementalHandler:(nullable TMURLSessionRequestIncrementedHandler)incrementalHandler
                            progressHandler:(nullable TMURLSessionRequestProgressHandler)progressHandler
                          completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {
    NSParameterAssert(request);

    NSParameterAssert(completionHandler);

    TMMultipartEncodedForm *form;
    // If the requestBody is of type TMMultiPartRequestBodyProtocol we should use `encodeWithError:` to be able to encode into a file in a memory efficient way.
    if ([request.requestBody conformsToProtocol:@protocol(TMMultiPartRequestBodyProtocol)]) {
        id<TMMultiPartRequestBodyProtocol> multiPartBody = (id<TMMultiPartRequestBodyProtocol>)request.requestBody;
        NSError *encodingError;
        form = [multiPartBody encodeWithError:&encodingError];
        NSAssert(encodingError == nil, @"Failed to encode multipart body request.");
        if (encodingError) {
            form = nil;
        }
    }
    // If encountered an error, try putting the whole data in the upload file at once.
    if (!form) {
        NSData *bodyData = [request.requestBody bodyData];
        form = [[TMMultipartEncodedForm alloc] initWithData:bodyData];
    }

    NSURLSessionTask *task = [[[TMUploadSessionTaskCreator alloc] initWithFilePath:form.fileURL
                                                                           session:self.session
                                                                           request:[self paramaterizedRequestFromRequest:request]
                                                                          bodyData:form.data
                                                                incrementalHandler:incrementalHandler
                                                                 completionHandler:completionHandler] uploadTask];
    [self.observer addSessionTask:task];

    if (incrementalHandler || progressHandler) {
        [self.concreteURLSessionTaskDelegate addSessionTask:task
                                          completionHandler:completionHandler
                                         incrementalHandler:incrementalHandler ?: ^(NSData * _Nullable data, NSURLSessionDataTask * _Nonnull dataTask) { }
                                            progressHandler:progressHandler ?: ^(double progess, NSURLSessionTask * _Nonnull dataTask) { }];
    }

    return task;
}

- (nonnull NSURLRequest *)paramaterizedRequestFromRequest:(nonnull id <TMRequest>)request {
    NSParameterAssert(request);

    const TMRequestParamaterizer *parametizer = [[TMRequestParamaterizer alloc] initWithApplicationCredentials:self.applicationCredentials
                                                                                               userCredentials:self.userCredentials
                                                                                                       request:request
                                                                                             additionalHeaders:self.additionalHeaders];
    return [parametizer URLRequestWithRequest:request];
}

#pragma mark - Private

- (nonnull NSURLSessionDataTask *)sessionTaskWithURLRequest:(nonnull NSURLRequest *)request {
    NSParameterAssert(request);

    return [self.session dataTaskWithRequest:request];
}

- (nonnull NSURLSessionDataTask *)sessionTaskWithURLRequest:(nonnull NSURLRequest *)request
                                          completionHandler:(nonnull TMURLSessionRequestCompletionHandler)completionHandler {
    NSParameterAssert(request);
    NSParameterAssert(completionHandler);
    
    return [self.session dataTaskWithRequest:request
                           completionHandler:completionHandler];
}

- (nonnull NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [NSURLSession sessionWithConfiguration:configuration
                                         delegate:self.customURLSessionDataDelegate ?: self.concreteURLSessionTaskDelegate
                                    delegateQueue:nil];
}

- (nonnull instancetype)copyWithNewConfiguration:(nonnull NSURLSessionConfiguration *)configuration {
    NSParameterAssert(configuration);
    return [[[self class] alloc] initWithConfiguration:configuration
                                applicationCredentials:self.applicationCredentials
                                       userCredentials:self.userCredentials
                                networkActivityManager:self.networkActivityManager
                             sessionTaskUpdateDelegate:self.sessionTaskUpdateDelegate
                                sessionMetricsDelegate:self.sessionMetricsDelegate
                                    requestTransformer:self.requestTransformer
                          customURLSessionDataDelegate:self.customURLSessionDataDelegate
                                     additionalHeaders:self.additionalHeaders];
}

- (void)finishTasksAndInvalidate {
    [self.session finishTasksAndInvalidate];
}

- (void)invalidateAndCancel {
    [self.session invalidateAndCancel];
}

@end
