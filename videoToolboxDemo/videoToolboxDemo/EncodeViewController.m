//
//  EncodeViewController.m
//  videoToolboxDemo
//
//  Created by liangweidong on 2019/2/19.
//  Copyright © 2019 liangweidong. All rights reserved.
//

#import "EncodeViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

/**
 https://www.jianshu.com/p/eccdcf43d7d2 参考文章
 https://www.jianshu.com/p/7a38378a7a1c?utm_campaign=hugo&utm_medium=reader_share&utm_content=note&utm_source=weixin-friends 这是cc老师的音视频文章
 */

@interface EncodeViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong)AVCaptureSession *captureSession;
@property(nonatomic, strong)AVCaptureDeviceInput *captureDeviceInput;
@property(nonatomic, strong)AVCaptureVideoDataOutput *captureVideoDataOutput;
@property(nonatomic, strong)AVCaptureConnection *captureConnection;
@property(nonatomic, strong)AVCaptureVideoPreviewLayer *videoPreviewLayer;

/*******************************************/
@property(nonatomic, strong)dispatch_queue_t cEncodeQueue;
@property(nonatomic, assign)NSInteger frameID;
@property(nonatomic, assign)VTCompressionSessionRef cEncodeingSession;

@property(nonatomic, strong)NSFileHandle *fileHandele;
@property(nonatomic, strong)NSString *filePath;

@end

@implementation EncodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.filePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.filePath =[NSString stringWithFormat:@"%@/test.txt",self.filePath];
    BOOL isFile = [[NSFileManager defaultManager] createFileAtPath:self.filePath contents:nil attributes:nil];
    if (!isFile)
    {
        NSLog(@"文件创建失败");
        return;
    }
    self.fileHandele = [NSFileHandle fileHandleForUpdatingAtPath:self.filePath];

    self.cEncodeQueue = dispatch_queue_create("lwd", DISPATCH_QUEUE_SERIAL);

    [self initConfigCamera];//初始化相机
    
    [self initEncode];//初始化编码数据
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
    [self.view.layer addSublayer:self.videoPreviewLayer];
    [self startCapture];
}
//上面的是所有的准备工作做好了，接下来就是开始采集了
-(BOOL)startCapture
{
    //先判断一下摄像头的权限
    AVAuthorizationStatus videoAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (videoAuthStatus != AVAuthorizationStatusAuthorized)
    {
        return NO;
    }
    [self.captureSession startRunning];
    return YES;
}
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate
/**
 摄像头采集的数据回调
 @param output 输出设备
 @param sampleBuffer 帧缓存数据，描述当前帧信息
 @param connection 连接
 */
-(void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(nonnull CMSampleBufferRef)sampleBuffer fromConnection:(nonnull AVCaptureConnection *)connection
{
    /** 4.循环获取采集数据 */
    dispatch_sync(self.cEncodeQueue, ^{
        [self videoDataEncode:sampleBuffer];
    });
}
/**
 VideoToolBox的编码过程：
 1，向VideoToolBox输入CVPixelBuufer类型的原始数据（在AVFoundation 回调方法中,它有提供我们的数据其实就是CVPixelBuffer.只不过当时使用的是引用类型CVImageBufferRef,其实就是CVPixelBuffer的另外一个定义.）
 2，VideoToolBox编码完之后会输出h264文件，是CMSampleBuffer--》CMBlockBuffer（Camera 返回的CVImageBuffer 中存储的数据是一个CVPixelBuffer,而经过VideoToolBox编码输出的CMSampleBuffer中存储的数据是一个CMBlockBuffer的引用.）
 */
-(void)initEncode
{
    /** 1.创建session--调用VTCompressionSessionCreate创建编码session */
    //参数1：NULL 分配器,设置NULL为默认分配
    //参数2：width
    //参数3：height
    //参数4：编码类型,如kCMVideoCodecType_H264
    //参数5：NULL encoderSpecification: 编码规范。设置NULL由videoToolbox自己选择
    //参数6：NULL sourceImageBufferAttributes: 源像素缓冲区属性.设置NULL不让videToolbox创建,而自己创建
    //参数7：NULL compressedDataAllocator: 压缩数据分配器.设置NULL,默认的分配
    //参数8：回调  当VTCompressionSessionEncodeFrame被调用压缩一次后会被异步调用.注:当你设置NULL的时候,你需要调用VTCompressionSessionEncodeFrameWithOutputHandler方法进行压缩帧处理,支持iOS9.0以上
    //参数9：outputCallbackRefCon: 回调客户定义的参考值
    //参数10：compressionSessionOut: 编码会话变量
    OSStatus status = VTCompressionSessionCreate(NULL,
                                                 720,
                                                 1280,
                                                 kCMVideoCodecType_H264,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 didCompressH264,
                                                 (__bridge void*)(self),
                                                 &_cEncodeingSession);
    if (status != noErr)
    {
        NSLog(@"创建session出问题了：%d", (int)status);
        return;
    }
    if (self.cEncodeingSession == NULL)
    {
        NSLog(@"VEVideoEncoder::调用顺序错误");
        return;
    }
    
    /** 2.设置编码相关参数  都是key-value形式，第一个参数就是session*/
    // ProfileLevel，h264的协议等级，不同的清晰度使用不同的ProfileLevel。(表示使用H264的Profile规格,可以设置Hight的AutoLevel规格.)
    CFStringRef profileRef = kVTProfileLevel_H264_Baseline_AutoLevel;
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_ProfileLevel, profileRef);
    if (status != noErr)
    {
        NSLog(@"设置编码参数的H264的Profile规格出问题了：%d", (int)status);
        return;
    }
    //设置是否实时编码
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    if (status != noErr)
    {
        NSLog(@"设置实时编码出问题了：%d", (int)status);
        return;
    }
    //配置是否产生B帧（表示是否使用产生B帧数据(因为B帧在解码是非必要数据,所以开发者可以抛弃B帧数据)）
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    if (status != noErr)
    {
        NSLog(@"设置是否产生B帧出问题了：%d", (int)status);
        return;
    }
    //配置I帧间隔（表示关键帧的间隔,也就是我们常说的gop size.）
    /**GOP概念
    两个I帧之间形成的一组图片,就是GOP(Group of Picture).
    通常在编码器设置参数时,必须会设置gop_size的值.其实就是代表2个I帧之间的帧数目. 在一个GOP组中容量最大的就是I帧.所以相对而言,gop_size设置的越大,整个视频画面质量就会越好.但是解码端必须从接收的第一个I帧开始才可以正确解码出原始图像.否则无法正确解码.
     */
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(15*240));//这里的值可以动态用参数来改变
    if (status != noErr)
    {
        NSLog(@"设置I帧间隔出问题了：%d", (int)status);
        return;
    }
    //设置期望帧率 kVTCompressionPropertyKey_ExpectedFrameRate
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_ExpectedFrameRate,(__bridge CFTypeRef)@(15));
    if (status != noErr)
    {
        NSLog(@"设置期望帧率出问题了：%d", (int)status);
        return;
    }
    
    //设置码率kVTCompressionPropertyKey_AverageBitRate(码率)/kVTCompressionPropertyKey_DataRateLimits（限制最大码率）
    status = VTSessionSetProperty(self.cEncodeingSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(512 * 1024));
    if (status != noErr)
    {
        NSLog(@"设置码率出问题了：%d", status);
        return;
    }
    
    /** 3.准备开始编码 */
    VTCompressionSessionPrepareToEncodeFrames(self.cEncodeingSession);
    
    /** 4.循环获取采集数据 */
    //在AVCapture的代理方法里面来videoDataEncode：把数据不停的送进去，让其编码
    
    /** 5.获取编码后数据 */
    //在videoDataEncode：方法里面会编码获得编码后的数据
    
    /** 6.将数据写入H264文件 */
    //didCompressH264函数
}
/** 5.获取编码后数据 */
-(void)videoDataEncode:(CMSampleBufferRef)sampleBuffer
{
    //按理说我们现在应该拿到CVPixelBuufer，作为输入数据，但是由上面解释可知，CVImageBufferRef就是CVPixelBuufer的另一个定义，所以我们这里先拿到CVImageBufferRef：
    //拿到每一帧未编码数据
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
 
    //设置帧时间，如果不设置会导致时间轴过长。时间戳以ms为单位
    CMTime presentationTimeStamp = CMTimeMake(self.frameID++, 1000);
    
    VTEncodeInfoFlags flags;
    /**
     参数1：编码会话变量
     参数2：未编码数据
     参数3：获取到的这个sample buffer数据的展示时间戳。每一个传给这个session的时间戳都要大于前一个展示时间戳.
     参数4：对于获取到sample buffer数据,这个帧的展示时间.如果没有时间信息,可设置kCMTimeInvalid.
     参数5：frameProperties: 包含这个帧的属性.帧的改变会影响后边的编码帧.
     参数6：ourceFrameRefCon: 回调函数会引用你设置的这个帧的参考值.
     参数7：infoFlagsOut: 指向一个VTEncodeInfoFlags来接受一个编码操作.如果使用异步运行,kVTEncodeInfo_Asynchronous被设置；同步运行,kVTEncodeInfo_FrameDropped被设置；设置NULL为不想接受这个信息.
     */
    OSStatus statusCode = VTCompressionSessionEncodeFrame(self.cEncodeingSession,
                                                          imageBuffer,
                                                    presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL,
                                                          NULL,
                                                          &flags);
    if (statusCode != noErr)
    {
        NSLog(@"编码的时候出问题了兄弟:%d", (int)statusCode);
        VTCompressionSessionInvalidate(self.cEncodeingSession);
//        CFRelease(self.cEncodeing Session);
        self.cEncodeingSession = NULL;
        return;
    }
    NSLog(@"编码成功");
    
}

//下面这个函数是当第5步编码成功之后，就会回调到这里
/** 编码数据处理-获取SPS/PPS
 当编码成功后,就会回调到最开始初始化编码器会话时传入的回调函数,回调函数的原型如下: */
void didCompressH264(void *outputCallbackRefCon,
                     void *sourceFrameRefCon,
                     OSStatus status,
                     VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer)
{
    //1.判断status,如果成功则返回0(noErr);成功则继续处理,不成功则不处理.
    if (status != noErr || sampleBuffer == nil)
    {
        return;
    }
    if (outputCallbackRefCon == nil)
    {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        return;
    }
    if (infoFlags & kVTEncodeInfo_FrameDropped)
    {
        return;
    }
    //2.判断是否关键帧
    /**
     为什么要判断关键帧呢?
     因为VideoToolBox编码器在每一个关键帧前面都会输出SPS/PPS信息.所以如果本帧是关键帧,则可以取出对应的SPS/PPS信息.
     */
    EncodeViewController *codevc = (__bridge EncodeViewController*)(outputCallbackRefCon);
    
    CFArrayRef arrayRef = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef theDict = (CFDictionaryRef)CFArrayGetValueAtIndex(arrayRef, 0);
    bool isKeyFrame = !CFDictionaryContainsKey(theDict, (const void *)kCMSampleAttachmentKey_NotSync);
    if (isKeyFrame)
    {
        NSLog(@"编码了一个关键帧");
        //这个对象就是图像存储方式，编码器等格式描述
        CMFormatDescriptionRef formatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        //关键帧需要加上SPS、PPS信息
        //sps
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef,
                                                                                 0,
                                                                                 &sparameterSet,
                                                                                 &sparameterSetSize,
                                                                                 &sparameterSetCount,
                                                                                 0);
        if (statusCode != noErr)
        {
            NSLog(@"sps出问题了");
            return;
        }
        //获取pps
        size_t ppsSetSize, ppsSetCount;
        const uint8_t *pparameterSet;
        //从第一个关键帧获取sps & pps
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef,
                                                                        0,
                                                                        &pparameterSet,
                                                                        &ppsSetSize,
                                                                        &ppsSetCount,
                                                                        0);
        //获取h264参数集合中的sps和pps
        if (statusCode == noErr)
        {
            NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
            NSData *pps = [NSData dataWithBytes:pparameterSet length:ppsSetSize];
            
            if (codevc)
            {
                [codevc gotSpsPps:sps pps:pps];
            }
        }
    }
    /**
     编码压缩数据并写入H264文件
     当我们获取了SPS/PPS信息之后,我们就获取实际的内容来进行处理了
     */
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr)
    {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;//返回的nalu数据前4个字节不是001的startcode,而是大端模式的帧长度length
        //循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength)
        {
            uint32_t NALUnitLength = 0;
           
            //读取一单元长度的nalu
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            //从大端模式转换为系统端模式
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            //获取nalu数据
            NSData *data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            
            //将nalu数据写入到文件
            [codevc gotEncodedData:data isKeyFrame:isKeyFrame];
            
            //读取下一个nalu 一次回调可能包含多个nalu数据
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}
//第一帧写入 sps & pps
-(void)gotSpsPps:(NSData *)sps pps:(NSData *)pps
{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
    [self.fileHandele writeData:byteHeader];
    [self.fileHandele writeData:sps];
    [self.fileHandele writeData:byteHeader];
    [self.fileHandele writeData:pps];
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    if (self.fileHandele != NULL)
    {
        //添加4个字节的H264 协议 start code 分割符
        //一般来说编码器编出的首帧数据为PPS & SPS
        //H264编码时，在每个NAL前添加起始码 0x000001,解码器在码流中检测起始码，当前NAL结束。
        /*
         为了防止NAL内部出现0x000001的数据，h.264又提出'防止竞争 emulation prevention"机制，在编码完一个NAL时，如果检测出有连续两个0x00字节，就在后面插入一个0x03。当解码器在NAL内部检测到0x000003的数据，就把0x03抛弃，恢复原始数据。
         
         总的来说H264的码流的打包方式有两种,一种为annex-b byte stream format 的格式，这个是绝大部分编码器的默认输出格式，就是每个帧的开头的3~4个字节是H264的start_code,0x00000001或者0x000001。
         另一种是原始的NAL打包格式，就是开始的若干字节（1，2，4字节）是NAL的长度，而不是start_code,此时必须借助某个全局的数据来获得编 码器的profile,level,PPS,SPS等信息才可以解码。
         */
        const char bytes[] = "\0x00\0x00\0x00\0x01";
        //长度
        size_t length = (sizeof bytes) - 1;
        
        //头字节
        NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
        
        //写入头字节
        [self.fileHandele writeData:byteHeader];
        
        //写入h264数据
        [self.fileHandele writeData:data];
    }
}
- (void)dealloc
{
    NSLog(@"%s", __func__);
    if (NULL == self.cEncodeingSession)
    {
        return;
    }
    VTCompressionSessionCompleteFrames(self.cEncodeingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(self.cEncodeingSession);
//    CFRelease(_compressionSessionRef);
    self.cEncodeingSession = NULL;
}
@end

