#include <leptonica/allheaders.h>
#include <png.h>
#include <tiffio.h>
#include <stdio.h>
#include <stdlib.h>
static void require(int ok,const char *name){if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
int main(void){
    char *version=getLeptonicaVersion();printf("%s; PNG %s; %s\n",version,png_get_libpng_ver(NULL),TIFFGetVersion());lept_free(version);
    PIX *pix=pixCreate(24,16,8);require(pix!=NULL,"allocate image");
    for(int y=0;y<16;y++)for(int x=0;x<24;x++)pixSetPixel(pix,x,y,(x*9+y*3)%256);
    unsigned char *data=NULL;size_t size=0;int same=0;
    require(pixWriteMemPng(&data,&size,pix,0)==0 && size>0,"PNG encode");PIX *read=pixReadMemPng(data,size);
    require(read && pixEqual(pix,read,&same)==0 && same,"PNG lossless decode");pixDestroy(&read);lept_free(data);data=NULL;
    require(pixWriteMemTiff(&data,&size,pix,IFF_TIFF_LZW)==0 && size>0,"TIFF encode");read=pixReadMemTiff(data,size,0);
    require(read && pixEqual(pix,read,&same)==0 && same,"TIFF lossless decode");pixDestroy(&read);lept_free(data);data=NULL;
    require(pixWriteMemJpeg(&data,&size,pix,85,0)==0 && size>0,"JPEG encode");read=pixReadMemJpeg(data,size,0,1,NULL,0);
    require(read && pixGetWidth(read)==24 && pixGetHeight(read)==16,"JPEG decode");pixDestroy(&read);lept_free(data);pixDestroy(&pix);
    puts("PASS: PNG/TIFF lossless and JPEG encode/decode");return 0;
}
