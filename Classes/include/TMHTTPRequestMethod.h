//
//  TMHTTPRequestMethod.h
//  TMTumblrSDK
//
//  Created by Kenny Ackerson on 11/18/15.
//
//
@import Foundation;
/**
 *  Enum representing request methods.
 */
typedef NS_ENUM(int, TMHTTPRequestMethod) {
    /**
     *  GET
     */
    TMHTTPRequestMethodGET,
    /**
     *  POST
     */
    TMHTTPRequestMethodPOST,
    /**
     *  DELETE
     */
    TMHTTPRequestMethodDELETE,
    /**
     *  PUT
     */
    TMHTTPRequestMethodPUT,
    /**
     *  HEAD
     */
    TMHTTPRequestMethodHEAD,
    /**
    * Patch
    */
    TMHTTPRequestMethodPATCH,
};
