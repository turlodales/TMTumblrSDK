//
//  TMMultipartRequestBody.m
//  Pods
//
//  Created by Kenny Ackerson on 5/10/16.
//
//

#import "TMMultipartRequestBody.h"
#import "TMMultipartConstants.h"
#import "TMMultipartUtil.h"

NSUInteger const TMMultipartFormFileEncodingThreshold = 10 * 1024 * 1024; //10MB

@interface TMMultipartRequestBody ()

@property (nonatomic, readonly, nonnull) NSArray<NSString *> *filePaths;
@property (nonatomic, readonly, nonnull) NSArray<NSString *> *contentTypes;
@property (nonatomic, readonly, nonnull) NSArray<NSString *> *fileNames;
@property (nonatomic, readonly, nonnull) NSDictionary *parameters;
@property (nonatomic, readonly, nonnull) NSArray <NSString *> *keys;
@property (nonatomic) BOOL encodeJSONBody;
@property (nonatomic) NSUInteger fileEncodingThreshold;
@property (nonatomic) TMEncodableMultipartFormData *encodableFormData;

@end

@implementation TMMultipartRequestBody

- (nonnull instancetype)initWithFilePaths:(nonnull NSArray<NSString *> *)filePaths
                             contentTypes:(nonnull NSArray<NSString *> *)contentTypes
                                fileNames:(nonnull NSArray<NSString *> *)fileNames
                               parameters:(nonnull NSDictionary *)parameters
                                     keys:(nonnull NSArray <NSString *> *)keys
                           encodeJSONBody:(BOOL)encodeJSONBody
                    fileEncodingThreshold:(NSUInteger)fileEncodingThreshold {
    NSParameterAssert(filePaths);
    NSParameterAssert(contentTypes);
    NSParameterAssert(fileNames);
    NSParameterAssert(parameters);
    NSParameterAssert(keys);
    
    NSParameterAssert(fileNames.count == filePaths.count);
    NSParameterAssert(filePaths.count == contentTypes.count);
    NSParameterAssert(filePaths.count == keys.count);
    
    self = [super init];
    
    if (self) {
        _filePaths = filePaths;
        _contentTypes = contentTypes;
        _fileNames = fileNames;
        _parameters = parameters;
        _keys = keys;
        _encodeJSONBody = encodeJSONBody;
        _fileEncodingThreshold = fileEncodingThreshold;
    }
    
    return self;
}

- (instancetype)initWithFilePaths:(NSArray<NSString *> *)filePaths
                     contentTypes:(NSArray<NSString *> *)contentTypes
                        fileNames:(NSArray<NSString *> *)fileNames
                       parameters:(NSDictionary *)parameters
                             keys:(NSArray <NSString *> *)keys
                   encodeJSONBody:(BOOL)encodeJSONBody {
    return [self initWithFilePaths:filePaths contentTypes:contentTypes fileNames:fileNames parameters:parameters keys:keys encodeJSONBody:encodeJSONBody fileEncodingThreshold:TMMultipartFormFileEncodingThreshold];
}

- (nonnull NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, %@, %@>", NSStringFromClass([self class]), self, self.contentType, self.parameters];
}

#pragma mark - TMRequestBody

- (nullable NSString *)contentType {
    return [[NSString alloc] initWithFormat:@"multipart/form-data; charset=utf-8; boundary=%@", TMMultipartBoundary];
}

- (nullable NSString *)contentEncoding {
    return nil;
}

- (TMMultipartEncodedForm *)encodeWithError:(NSError **)error {
    [self build:error];
    if (*error) {
        return nil;
    }
    
    NSData *data = nil;
    NSURL *url = nil;
    if (self.encodableFormData.totalContentLength > self.fileEncodingThreshold) {
        url = [self doEncodeIntoFileWithError:error];
        if (*error) {
            return nil;
        }
        return [[TMMultipartEncodedForm alloc] initWithFileURL:url data:data];
    }
    else {
        data = [self.encodableFormData encodeIntoDataWithError:error];
        return [[TMMultipartEncodedForm alloc] initWithData:data];
    }
}

- (NSURL *)encodeIntoFileWithError:(NSError **)error {
    [self build:error];
    if (*error) {
        return nil;
    }
    return [self doEncodeIntoFileWithError:error];
}

- (NSURL *)doEncodeIntoFileWithError:(NSError **)error {
    NSURL *fileURL = [TMMultipartUtil createTempFileWithError:error];
    if (*error) {
        return nil;
    }
    [self.encodableFormData encodeIntoFileWithURL:fileURL error:error];
    return fileURL;
}

- (void)build:(NSError **)error {
    TMEncodableMultipartFormData *encodableFormData = [[TMEncodableMultipartFormData alloc] initWithFileManager:[NSFileManager defaultManager] boundary:TMMultipartBoundary];
    const BOOL multiple = [self hasMultipleDistinctFiles];
    
    __block NSError *fileError;
    [self.filePaths enumerateObjectsUsingBlock:^(NSString *filePath, NSUInteger index, BOOL *stop) {
        
        if ([filePath isKindOfClass:[NSNull class]]) {
            return;
        }
        
        NSString *key = self.keys[index];
        NSAssert(key, @"We must have a key here or else the multipart request body is invalid.");
        
        [encodableFormData appendFilePath:filePath
                                     name:multiple ? [NSString stringWithFormat:@"%@[%lu]", key, (unsigned long)index] : key
                              contentType:self.contentTypes[index]
                                    error:&fileError];
        if (fileError) {
            *stop = YES;
        }
    }];
    
    if (fileError) {
        *error = fileError;
        return;
    }
    
    NSDictionary *parameters = self.parameters;
    
    if (self.encodeJSONBody) {
        NSData *JSONData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:NULL];
        
        if (JSONData) {
            [encodableFormData appendData:JSONData
                                     name:@"json"
                                 fileName:nil
                              contentType:@"application/json; charset=utf-8"];
        }
    }
    else {
        for (NSString *key in [parameters allKeys]) {
            [encodableFormData appendData:[parameters[key] dataUsingEncoding:NSUTF8StringEncoding]
                                     name:key
                                 fileName:nil
                              contentType:@"text/plain; charset=utf-8"];
        }
    }
    self.encodableFormData = encodableFormData;
}

- (nullable NSData *)bodyData {
    NSError *error;
    
    [self build:&error];
    if (error) {
        return nil;
    }
    
    NSData *result = [self.encodableFormData encodeIntoDataWithError:&error];
    if (error) {
        return nil;
    }
    
    return result;
}

- (BOOL)encodeParameters {
    return NO;
}

#pragma mark - Private

- (BOOL)hasMultipleDistinctFiles {
    
    NSMutableSet *temporaryContainer = [[NSMutableSet alloc] init];
    
    for (NSString *key in self.keys) {
        if ([temporaryContainer containsObject:key]) {
            return YES;
        }
        
        [temporaryContainer addObject:key];
    }
    
    return NO;
}

@end
