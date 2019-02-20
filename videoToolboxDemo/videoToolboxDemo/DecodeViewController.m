//
//  DecodeViewController.m
//  videoToolboxDemo
//
//  Created by liangweidong on 2019/2/19.
//  Copyright © 2019 liangweidong. All rights reserved.
//

#import "DecodeViewController.h"

@interface DecodeViewController ()

@end

@implementation DecodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}
/**
 解析nalu数据
 */
-(void)decodeNaluData:(NSData *)naluData
{
    uint8_t *frame = (uint8_t *)naluData.bytes;
    uint32_t frameSize = (uint32_t)naluData.length;
    //frame的前四位是nalu数据的开始码，也就是00 00 00 01
    //第5个字节是表示数据类型，转为10进制后，7是sps， 8是pps，5是IDR(I帧)信息
    int nalu_type = (frame[4] & 0x1F);
    
    //将nalu的开始码替换成nalu的长度信息
//    uin
}

















@end
