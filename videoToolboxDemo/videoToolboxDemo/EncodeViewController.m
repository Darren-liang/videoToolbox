//
//  EncodeViewController.m
//  videoToolboxDemo
//
//  Created by liangweidong on 2019/2/19.
//  Copyright © 2019 liangweidong. All rights reserved.
//

#import "EncodeViewController.h"
#import <AVFoundation/AVFoundation.h>

/**
 https://www.jianshu.com/p/eccdcf43d7d2 参考文章
 */

@interface EncodeViewController ()
@property(nonatomic, strong)AVCaptureSession *captureSession;
@property(nonatomic, strong)AVCaptureDeviceInput *captureDeviceInput;
@property(nonatomic, strong)AVCaptureVideoDataOutput *captureVideoDataOutput;
@property(nonatomic, strong)AVCaptureConnection *captureConnection;
@property(nonatomic, strong)AVCaptureVideoPreviewLayer *videoPreviewLayer;

@end

@implementation EncodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initConfigCamera];
}
-(void)initConfigCamera
{
    //获取到所有摄像头
    NSArray *cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //获取后置摄像头
    NSArray *captureDeviceArray = [cameras filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"position == %d", AVCaptureDevicePositionBack]];
    //判断是否成功获取到了
    if (!captureDeviceArray.count)
    {
        NSLog(@"获取前置摄像头失败");
        return;
    }
    //转化为输入设备
    AVCaptureDevice *camera = captureDeviceArray.firstObject;
    NSError *errorMessage = nil;
    self.captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&errorMessage];
    if (errorMessage)
    {
        NSLog(@"AVCaptureDevice转AVCaptureDeviceInput失败");
        return;
    }
    
/*************************************************************/
    
    //设置视频输出
    self.captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    //设置视频输出格式
    /**
     视频输出格式选的是kCVPixelFormatType_420YpCbCr8BiPlanarFullRange，YUV数据格式，不理解YUV数据的概念的话可以先这么写，后面编解码再深入了解YUV数据格式
     */
    NSDictionary *videoSetting = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange], kCVPixelBufferPixelFormatTypeKey, nil];
    [self.captureVideoDataOutput setVideoSettings:videoSetting];
    
    //设置输出代理，串行队列和数据回调
    dispatch_queue_t outputQueue = dispatch_queue_create("lwd", DISPATCH_QUEUE_SERIAL);
    [self.captureVideoDataOutput setSampleBufferDelegate:self queue:outputQueue];
    //丢弃延迟的帧率
    self.captureVideoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    
    /*************************************************************/
    
    //AVCaptureSession对象是用来管理采集数据和输出数据的，它负责协调从哪里采集数据，输出到哪里。
    self.captureSession = [[AVCaptureSession alloc] init];
    //不使用应用的实例，避免被一场挂断
    self.captureSession.usesApplicationAudioSession = NO;
    //添加输入设备到会话
    /**
     captureDeviceInput绑定了摄像头，作为输入源，吧摄像头采集到的数据源源不断的给送进来
     captureVideoDataOutput输出源，把收到的数据展示在咱们自己的视图view上
     那么他俩怎么关联的呢，就是通过captureSession把他们连个关联起来
     */
    if ([self.captureSession canAddInput:self.captureDeviceInput])
    {
        [self.captureSession addInput:self.captureDeviceInput];
    }
    if ([self.captureSession canAddOutput:self.captureVideoDataOutput])
    {
        [self.captureSession addOutput:self.captureVideoDataOutput];
    }
    
    //设置分辨率
    if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720])
    {
        self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;//设置分辨率为720p
    }
    //获取连接并设置视频方向为竖屏方向
    self.captureConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    self.captureConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    //设置是否为镜像，因为如果是前置摄像头的话采集到的数据本来就是翻转的
    //这里设置镜像给转回来
    if (camera.position == AVCaptureDevicePositionFront &&
        self.captureConnection.supportsVideoMirroring)
    {//前置摄像头  是否支持镜像
        self.captureConnection.videoMirrored = YES;
    }
    
    //数据都有了
    //获取预览的layer，最后赋值给我门的view就可以展示了--还是通过我们session来获取到layer
    self.videoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    //设置展示的视频方向
    self.videoPreviewLayer.connection.videoOrientation = self.captureConnection.videoOrientation;
    self.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
