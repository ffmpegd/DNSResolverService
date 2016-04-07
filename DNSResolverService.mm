//
//  DNSResolverService.m
//  
//
//  Created by joe on 15/12/11.
//  Copyright © 2015年 joe. All rights reserved.
//

#import "DNSResolverService.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>

#include <arpa/inet.h>


#define DNS_SVR "114.114.114.114"

#define DNS_HOST  0x01
#define DNS_CNAME 0x05

int socketfd;

struct sockaddr_in dest;

static void send_dns_request(const char *dns_name);

//static void parse_dns_response();

/**
 * Generate DNS question chunk
 */
static void generate_question(const char *dns_name
                              , unsigned char *buf , int *len);

/**
 * Check whether the current byte is
 * a dns pointer or a length
 */
static int is_pointer(int in);

/**
 * Parse data chunk into dns name
 * @param chunk The complete response chunk
 * @param ptr The pointer points to data
 * @param out This will be filled with dns name
 * @param len This will be filled with the length of dns name
 */
static void parse_dns_name(unsigned char *chunk , unsigned char *ptr , char *out , int *len);

@implementation DNSResolverService

+ (NSArray *)getIPByHost:(NSString *)host
{
    socketfd = socket(AF_INET , SOCK_DGRAM , 0);
    if(socketfd < 0){
        perror("create socket failed");
        exit(-1);
    }
    struct timeval timeout = {1,0};
    //    setsockopt(socketfd, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout,sizeof(struct timeval));//设置发送超时
    setsockopt(socketfd, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,sizeof(struct timeval));//设置接收超时
    bzero(&dest , sizeof(dest));
    dest.sin_family = AF_INET;
    dest.sin_port = htons(53);
    dest.sin_addr.s_addr = inet_addr(DNS_SVR);
    
    send_dns_request([host UTF8String]);
    NSArray *resIps = [self parse_dns_response];
    //    NSLog(@"%@",resIps.description);
    return resIps;
}


+ (NSMutableArray *)parse_dns_response
{
    NSMutableArray *resIps = [NSMutableArray array];
    
    unsigned char buf[1024];
    unsigned char *ptr = buf;
    struct sockaddr_in addr;
    //    char *src_ip;
    int n , i , flag , querys , answers;
    int type , ttl , datalen , len;
    char cname[128] , aname[128] , ip[20];
    //    cname_ptr
    unsigned char netip[4];
    socklen_t addr_len = sizeof(struct sockaddr);
    
    //    n = recvfrom(socketfd , buf , sizeof(buf) , 0 , (struct sockaddr*)&addr , &addr_len);
    n = (int)recvfrom(socketfd , buf , sizeof(buf) , 0 , (struct sockaddr*)&addr , &addr_len);
    ptr += 4; /* move ptr to Questions */
    querys = ntohs(*((unsigned short*)ptr));
    ptr += 2; /* move ptr to Answer RRs */
    answers = ntohs(*((unsigned short*)ptr));
    ptr += 6; /* move ptr to Querys */
    
    size_t tmpLen = strlen((const char *)ptr);
    if (tmpLen <= querys) {
        return resIps;
    }
    
    /* move over Querys */
    for(i= 0 ; i < querys ; i ++){
        for(;;){
            flag = (int)ptr[0];
            ptr += (flag + 1);
            if(flag == 0)
                break;
        }
        ptr += 4;
    }
    //    printf("-------------------------------\n");
    /* now ptr points to Answers */
    for(i = 0 ; i < answers ; i ++){
        bzero(aname , sizeof(aname));
        len = 0;
        parse_dns_name(buf , ptr , aname , &len);
        ptr += 2; /* move ptr to Type*/
        type = htons(*((unsigned short*)ptr));
        ptr += 4; /* move ptr to Time to live */
        ttl = htonl(*((unsigned int*)ptr));
        ptr += 4; /* move ptr to Data lenth */
        datalen = ntohs(*((unsigned short*)ptr));
        ptr += 2; /* move ptr to Data*/
        if(type == DNS_CNAME){
            bzero(cname , sizeof(cname));
            len = 0;
            parse_dns_name(buf , ptr , cname , &len);
            //            printf("%s is an alias for %s\n" , aname , cname);
            ptr += datalen;
        }
        if(type == DNS_HOST){
            bzero(ip , sizeof(ip));
            if(datalen == 4){
                memcpy(netip , ptr , datalen);
                inet_ntop(AF_INET , netip , ip , sizeof(struct sockaddr));
                //                printf("%s has address %s\n" , aname , ip);
                //                printf("\tTime to live: %d minutes , %d seconds\n"
                //                       , ttl / 60 , ttl % 60);
                
                [resIps addObject:[NSString stringWithFormat:@"%s",ip]];
            }
            ptr += datalen;
        }
        
    }
    ptr += 2;
    
    return resIps;
}

static void parse_dns_name(unsigned char *chunk , unsigned char *ptr , char *out , int *len){
    int n , flag;
    char *pos = out + (*len);
    
    for(;;){
        flag = (int)ptr[0];
        if(flag == 0)
            break;
        if(is_pointer(flag)){
            n = (int)ptr[1];
            ptr = chunk + n;
            parse_dns_name(chunk , ptr , out , len);
            break;
        }else{
            ptr ++;
            memcpy(pos , ptr , flag);
            pos += flag;
            ptr += flag;
            *len += flag;
            if((int)ptr[0] != 0){
                memcpy(pos , "." , 1);
                pos += 1;
                (*len) += 1;
            }
        }
    }
    
}

static int is_pointer(int in){
    return ((in & 0xc0) == 0xc0);
}

static void send_dns_request(const char *dns_name){
    
    unsigned char request[256];
    unsigned char *ptr = request;
    unsigned char question[128];
    int question_len;
    
    
    generate_question(dns_name , question , &question_len);
    
    *((unsigned short*)ptr) = htons(0xff00);
    ptr += 2;
    *((unsigned short*)ptr) = htons(0x0100);
    ptr += 2;
    *((unsigned short*)ptr) = htons(1);
    ptr += 2;
    *((unsigned short*)ptr) = 0;
    ptr += 2;
    *((unsigned short*)ptr) = 0;
    ptr += 2;
    *((unsigned short*)ptr) = 0;
    ptr += 2;
    memcpy(ptr , question , question_len);
    ptr += question_len;
    
    sendto(socketfd , request , question_len + 12 , 0 , (struct sockaddr*)&dest , sizeof(struct sockaddr));
}

static void generate_question(const char *dns_name , unsigned char *buf , int *len){
    char *pos;
    unsigned char *ptr;
    int n;
    
    *len = 0;
    ptr = buf;
    pos = (char*)dns_name;
    for(;;){
        n = strlen(pos) - (strstr(pos , ".") ? strlen(strstr(pos , ".")) : 0);
        *ptr ++ = (unsigned char)n;
        memcpy(ptr , pos , n);
        *len += n + 1;
        ptr += n;
        if(!strstr(pos , ".")){
            *ptr = (unsigned char)0;
            ptr ++;
            *len += 1;
            break;
        }
        pos += n + 1;
    }
    *((unsigned short*)ptr) = htons(1);
    *len += 2;
    ptr += 2;
    *((unsigned short*)ptr) = htons(1);
    *len += 2;
}
@end
