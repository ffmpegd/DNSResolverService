//
//  DNSResolverService.h
//  
//
//  Created by joe on 15/12/11.
//  Copyright © 2015年 joe. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DNSResolverService : NSObject

+ (NSArray *)getIPByHost:(NSString *)host;

@end
