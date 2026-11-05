#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <MP42Foundation/MP42Foundation.h>
#import "MP42TextRecognizer.h"
#include <tesseract/baseapi.h>
extern "C" char *getLeptonicaVersion(void);
static void require(BOOL ok, NSString *message) { if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
int main(int argc,const char *argv[]) { @autoreleasepool {
    const char *version=tesseract::TessBaseAPI::Version();
    char *leptonica=getLeptonicaVersion();
    printf("Runtime Tesseract: %s; Leptonica: %s\n",version,leptonica);
    if(argc<2 || strcmp(argv[1],"--allow-old")) {
        require(strcmp(version,"5.5.4")==0,@"The app must actually link Tesseract 5.5.4");
        require(strstr(leptonica,"1.87.0")!=NULL,@"The app must actually link Leptonica 1.87.0");
    }
    free(leptonica);
    const size_t width=1200,height=180,stride=width*4;
    void *pixels=calloc(height,stride);CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,stride,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    require(context!=NULL,@"Create synthetic text image");
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,width,height));
    CTFontRef font=CTFontCreateWithName(CFSTR("Helvetica"),64,NULL);
    NSDictionary *attributes=@{(id)kCTFontAttributeName:(__bridge id)font,(id)kCTForegroundColorAttributeName:(__bridge id)CGColorGetConstantColor(kCGColorBlack)};
    NSAttributedString *string=[[NSAttributedString alloc] initWithString:@"SUBLER OCR 12345" attributes:attributes];
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGContextSetTextPosition(context,45,65);CTLineDraw(line,context);
    CGImageRef image=CGBitmapContextCreateImage(context);
    Class cls=NSClassFromString(@"MP42TesseractOCR");require(cls!=Nil,@"Find app's real OCR implementation");
    // English also exercises an existing legacy model if the user has one;
    // the undefined-language path exercises the existing English fallback.
    for (NSString *language in @[@"en",@"und"]) {
        id<MP42TextRecognizer> ocr=[(id<MP42TextRecognizer>)[cls alloc] initWithLanguage:language];
        require(ocr!=nil,@"Initialize existing OCR wrapper/model selection");
        NSString *text=[ocr performOCROnCGImage:image];
        NSString *normalized=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
        require([normalized isEqualToString:@"SUBLEROCR12345"], [NSString stringWithFormat:@"Recognize generated text (%@), got %@",language,text]);
        printf("PASS: existing app OCR wrapper (%s) recognizes SUBLER OCR 12345\n",language.UTF8String);
    }
    CGImageRelease(image);CFRelease(line);CFRelease(font);CGContextRelease(context);CGColorSpaceRelease(colors);free(pixels);
} return 0; }
