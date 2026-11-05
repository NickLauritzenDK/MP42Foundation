#import <AppKit/AppKit.h>
#import "MP42AC3AudioEncoder.h"
#import "MP42AudioEncoder.h"
// Private class declaration: avoid mixing local and framework public header copies.
@interface MP42AudioDecoder : NSObject <MP42AudioUnit>
- (instancetype)initWithAudioFormat:(AudioStreamBasicDescription)format channelLayout:(AudioChannelLayout *)layout channelLayoutSize:(UInt32)size mixdownType:(MP42AudioMixdown)mix drc:(float)drc initialPadding:(UInt32)padding magicCookie:(NSData *)cookie error:(NSError **)error;
@property (nonatomic,readwrite) MP42AudioUnitOutput outputType;
@end
#import "MP42SampleBuffer.h"
#import <math.h>
@interface PCMUnit : NSObject <MP42AudioUnit>
@property (nonatomic) MP42AudioUnitOutput outputType;
@property (nonatomic, unsafe_unretained) id<MP42ConverterProtocol> outputUnit;
@property (nonatomic) AudioChannelLayout *inputLayout,*outputLayout;
@property (nonatomic) UInt32 inputLayoutSize,outputLayoutSize;
@property (nonatomic) AudioStreamBasicDescription inputFormat,outputFormat;
@end
@implementation PCMUnit
-(void)reconfigure {}
-(void)addSample:(MP42SampleBuffer *)s {}
-(MP42SampleBuffer *)copyEncodedSample {return nil;}
-(NSData *)magicCookie {return nil;}
@end
int main(int argc,const char **argv) { @autoreleasepool {
 PCMUnit *unit=[PCMUnit new];AudioStreamBasicDescription format={0};
 format.mSampleRate=48000;format.mChannelsPerFrame=2;format.mBytesPerFrame=8;format.mBytesPerPacket=8;format.mFramesPerPacket=1;unit.outputFormat=format;
 AudioChannelLayout layout={0};layout.mChannelLayoutTag=kAudioChannelLayoutTag_Stereo;unit.outputLayout=&layout;unit.outputLayoutSize=sizeof(layout);
 if(argc>2 && !strcmp(argv[2],"decode-rate")) {
  format.mSampleRate=96000;format.mFormatID=kAudioFormatLinearPCM;format.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;format.mBitsPerChannel=32;
  MP42AudioDecoder *decoder=[[MP42AudioDecoder alloc]initWithAudioFormat:format channelLayout:&layout channelLayoutSize:sizeof(layout) mixdownType:kMP42AudioMixdown_Stereo drc:0 initialPadding:0 magicCookie:nil error:nil];
  if(!decoder)return 13;
  decoder.outputType=MP42AudioUnitOutputPull;
  MP42SampleBuffer *pcm=[MP42SampleBuffer new];pcm->size=96000*8;pcm->data=calloc(1,pcm->size);[decoder addSample:pcm];
  MP42SampleBuffer *eof=[MP42SampleBuffer new];eof->flags=MP42SampleBufferFlagEndOfFile;[decoder addSample:eof];
  int frames=0;BOOL done=NO;NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while([deadline timeIntervalSinceNow]>0) {MP42SampleBuffer *s=[decoder copyEncodedSample];if(s){if(s->flags&MP42SampleBufferFlagEndOfFile){done=YES;break;}frames+=s->size/8;}else [NSThread sleepForTimeInterval:0.001];}
  printf("decoder rate conversion with EOF drain: %d frames expected48000\n",frames);return !done || frames!=48000;
 }
 MP42AC3AudioEncoder *encoder=[[MP42AC3AudioEncoder alloc]initWithInputUnit:unit bitRate:96 error:nil];encoder.outputType=MP42AudioUnitOutputPull;[encoder reconfigure];
 if(argc>2) {
  if(![encoder respondsToSelector:@selector(cancel)]) {puts("FAIL: audio encoder cannot cancel blocked input");return 10;}
  [NSThread sleepForTimeInterval:0.02];
  [encoder performSelector:@selector(cancel)];
  MP42AudioEncoder *aac=[[MP42AudioEncoder alloc]initWithInputUnit:unit bitRate:96 error:nil];
  if(![aac respondsToSelector:@selector(cancel)])return 11;
  [aac performSelector:@selector(cancel)];
  format.mFormatID=kAudioFormatLinearPCM;format.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;format.mBitsPerChannel=32;
  MP42AudioDecoder *decoder=[[MP42AudioDecoder alloc]initWithAudioFormat:format channelLayout:&layout channelLayoutSize:sizeof(layout) mixdownType:kMP42AudioMixdown_Stereo drc:0 initialPadding:0 magicCookie:nil error:nil];
  if(!decoder || ![decoder respondsToSelector:@selector(cancel)])return 12;
  [decoder performSelector:@selector(cancel)];
  puts("PASS: cancelled AC3/AAC encoders and decoder blocked on input");return 0;
 }
 MP42SampleBuffer *pcm=[MP42SampleBuffer new];pcm->size=(1536+137)*8;pcm->data=calloc(1,pcm->size);float *data=(void*)pcm->data;
 for(int i=0;i<1536;i++)data[2*i]=data[2*i+1]=0.2*sin(2*M_PI*440*i/48000);
 [encoder addSample:pcm];MP42SampleBuffer *eof=[MP42SampleBuffer new];eof->flags=MP42SampleBufferFlagEndOfFile;[encoder addSample:eof];
 NSMutableData *encoded=[NSMutableData new];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];BOOL done=NO;
 while([deadline timeIntervalSinceNow]>0) {MP42SampleBuffer *s=[encoder copyEncodedSample];if(s){if(s->flags&MP42SampleBufferFlagEndOfFile){done=YES;break;}[encoded appendBytes:s->data length:s->size];}else [NSThread sleepForTimeInterval:0.001];}
 return !done || ![encoded writeToFile:@(argv[1]) atomically:YES];
}}
