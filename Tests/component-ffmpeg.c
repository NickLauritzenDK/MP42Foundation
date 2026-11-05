#include <libavcodec/avcodec.h>
#ifndef MP42_FRAMEWORK_ONLY
#include <libavformat/avformat.h>
#include <libavfilter/avfilter.h>
#endif
#include <libavutil/avutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void require(int ok,const char *name){if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
static unsigned char buffer[512];static int length;
static void segment(int kind,const unsigned char *bytes,int size){buffer[length++]=kind;buffer[length++]=size>>8;buffer[length++]=size;memcpy(buffer+length,bytes,size);length+=size;}
int main(int argc,char **argv){
#ifdef MP42_FRAMEWORK_ONLY
    unsigned version=avcodec_version();
    printf("Actual framework libavcodec: %u.%u.%u\n",version>>16,(version>>8)&255,version&255);
    if(argc<2||strcmp(argv[1],"--allow-old"))require(version==AV_VERSION_INT(63,1,102),"The app must link the libavcodec release shipped with FFmpeg 9.0.2");
#else
    printf("Standalone FFmpeg archives: %s\n",av_version_info());
    if(argc<2||strcmp(argv[1],"--allow-old"))require(strcmp(av_version_info(),"9.0.2")==0,"Dependency archives must be FFmpeg 9.0.2");
#endif
    const enum AVCodecID decoders[]={AV_CODEC_ID_DVD_SUBTITLE,AV_CODEC_ID_HDMV_PGS_SUBTITLE,AV_CODEC_ID_AAC,AV_CODEC_ID_MP3,AV_CODEC_ID_MP2,AV_CODEC_ID_MP1,
      AV_CODEC_ID_AC3,AV_CODEC_ID_EAC3,AV_CODEC_ID_TRUEHD,AV_CODEC_ID_ALAC,AV_CODEC_ID_OPUS,AV_CODEC_ID_VORBIS,AV_CODEC_ID_FLAC,AV_CODEC_ID_MLP,AV_CODEC_ID_DTS,
      AV_CODEC_ID_PCM_F32BE,AV_CODEC_ID_PCM_F32LE,AV_CODEC_ID_PCM_F64BE,AV_CODEC_ID_PCM_F64LE,AV_CODEC_ID_PCM_S16BE,AV_CODEC_ID_PCM_S16LE,AV_CODEC_ID_PCM_S16LE_PLANAR,
      AV_CODEC_ID_PCM_S24BE,AV_CODEC_ID_PCM_S24LE,AV_CODEC_ID_PCM_S32BE,AV_CODEC_ID_PCM_S32LE,AV_CODEC_ID_PCM_S8,AV_CODEC_ID_PCM_U8,AV_CODEC_ID_PCM_U16BE,AV_CODEC_ID_PCM_U16LE,AV_CODEC_ID_PCM_U24BE,AV_CODEC_ID_PCM_U24LE};
    for(size_t i=0;i<sizeof(decoders)/sizeof(decoders[0]);i++)require(avcodec_find_decoder(decoders[i])!=NULL,"Preserve required decoder");
    require(avcodec_find_encoder(AV_CODEC_ID_AC3)!=NULL,"AC3 encoder");
#ifndef MP42_FRAMEWORK_ONLY
    require(avfilter_get_by_name("aresample")!=NULL,"Resampling filter");
    require(av_guess_format("opus",NULL,NULL)!=NULL,"Opus muxer");
#endif
    enum AVCodecID parsers[]={AV_CODEC_ID_H264,AV_CODEC_ID_HEVC,AV_CODEC_ID_OPUS};
    for(size_t i=0;i<3;i++){AVCodecParserContext *parser=av_parser_init(parsers[i]);require(parser!=NULL,"Preserve parser");av_parser_close(parser);}
    const unsigned char composition[]={0x07,0x80,0x04,0x38,0x10,0,0,0x80,0,0,1,0,0,0,0,0,10,0,10};
    const unsigned char window[]={1,0,0,10,0,10,0,4,0,2};
    const unsigned char palette[]={0,0,0,16,128,128,0,1,235,128,128,255};
    const unsigned char object[]={0,0,0,0xc0,0,0,16,0,4,0,2,1,1,1,1,0,0,1,1,1,1,0,0};
    segment(0x16,composition,sizeof(composition));segment(0x17,window,sizeof(window));segment(0x14,palette,sizeof(palette));segment(0x15,object,sizeof(object));segment(0x80,buffer,0);
    const AVCodec *decoder=avcodec_find_decoder(AV_CODEC_ID_HDMV_PGS_SUBTITLE);AVCodecContext *ctx=avcodec_alloc_context3(decoder);
    require(avcodec_open2(ctx,decoder,NULL)==0,"Initialize PGS decoder");AVPacket *packet=av_packet_alloc();
    require(av_new_packet(packet,length)==0,"Allocate PGS packet");memcpy(packet->data,buffer,length);
    AVSubtitle subtitle={0};int got=0;require(avcodec_decode_subtitle2(ctx,&subtitle,&got,packet)>=0&&got,"Decode synthetic PGS packet");
    require(subtitle.num_rects==1&&subtitle.rects[0]->w==4&&subtitle.rects[0]->h==2,"PGS bitmap dimensions");
    for(int y=0;y<2;y++)for(int x=0;x<4;x++)require(subtitle.rects[0]->data[0][y*subtitle.rects[0]->linesize[0]+x]==1,"PGS bitmap pixels");
    avsubtitle_free(&subtitle);av_packet_free(&packet);avcodec_free_context(&ctx);
#ifdef MP42_FRAMEWORK_ONLY
    puts("PASS: actual app framework version, 32 decoders, AC3 encoder, 3 parsers and synthetic PGS bitmap");
#else
    puts("PASS: standalone dependency archives: 32 decoders, AC3 encoder, 3 parsers, resampler, Opus muxer and PGS bitmap");
#endif
    return 0;
}
