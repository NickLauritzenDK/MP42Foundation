#include "audio_resample.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
 hb_audio_resample_t *r=hb_audio_resample_init(AV_SAMPLE_FMT_FLT,AV_CH_LAYOUT_STEREO,0,48000,0);
 hb_audio_resample_set_sample_rate(r,96000);
 if(hb_audio_resample_update(r))return 2;
 float *input=calloc(96000*2,sizeof(float));
 for(int i=0;i<96000;i++) input[2*i]=input[2*i+1]=sin(2*M_PI*440*i/96000);
 const uint8_t *in=(void*)input;uint8_t *out=NULL;int bytes=0,total=0;
 if(hb_audio_resample(r,&in,96000,&out,&bytes))return 3;
 total+=bytes/8;free(out);
 if (!r->resample_needed) { printf("FAIL: rate-only conversion bypassed: %d frames\n",total); return 1; }
 while(!hb_audio_resample(r,NULL,0,&out,&bytes)){total+=bytes/8;free(out);}
 free(input);hb_audio_resample_free(r);
 printf("rate-only conversion with drain: %d frames, expected48000\n",total);
 return total!=48000;
}
