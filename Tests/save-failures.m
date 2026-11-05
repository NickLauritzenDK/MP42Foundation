#import <AppKit/AppKit.h>
#import <MP42Foundation/MP42Foundation.h>
#import <objc/runtime.h>
@interface MP42Track (FailureTest)
- (BOOL)writeToFile:(MP42FileHandle)handle error:(NSError **)error;
@end
@interface FailingAudioTrack : MP42AudioTrack @end
@implementation FailingAudioTrack
- (BOOL)writeToFile:(MP42FileHandle)handle error:(NSError **)error {
 if(error)*error=[NSError errorWithDomain:@"InjectedTrackWriteFailure" code:42 userInfo:nil];
 return NO;
}
@end
static MP42Track *observedTrack;
static BOOL sawInitializedConverter;
@interface InvalidVideoImporter : MP42FileImporter @end
@implementation InvalidVideoImporter
- (NSData *)magicCookieForTrack:(MP42Track *)track { sawInitializedConverter = [observedTrack valueForKey:@"converter"] != nil; return [NSData dataWithBytes:"x" length:1]; }
@end
static int failures;
static void check(BOOL value,const char *message){printf("%s: %s\n",value?"PASS":"FAIL",message);if(!value)failures++;}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc!=3)return 2;
 NSFileManager *fm=NSFileManager.defaultManager;NSURL *dir=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
 [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
 NSURL *source=[dir URLByAppendingPathComponent:@"disposable.m4a"],*dest=[dir URLByAppendingPathComponent:@"missing.mp4"];
 [fm removeItemAtURL:source error:NULL];[fm copyItemAtURL:[NSURL fileURLWithPath:@(argv[1])] toURL:source error:NULL];
 NSError *error=nil;MP42FileImporter *importer=[[MP42FileImporter alloc]initWithURL:source error:&error];
 check(importer.tracks.count==1,"fixture imports");MP42File *file=[[MP42File alloc]init];
 for(MP42Track *t in importer.tracks){[file addTrack:t];[t setValue:nil forKey:@"importer"];}
 [fm removeItemAtURL:source error:NULL];
 NSData *sentinel=[@"existing destination must survive missing source" dataUsingEncoding:NSUTF8StringEncoding];[sentinel writeToURL:dest atomically:YES];
 error=nil;BOOL saved=[file writeToUrl:dest options:@{} error:&error];
 check(!saved && error!=nil,"missing source returns failure with error");
 check([[NSData dataWithContentsOfURL:dest]isEqual:sentinel],"missing source preserves existing destination");
 [fm copyItemAtURL:[NSURL fileURLWithPath:@(argv[1])] toURL:source error:NULL];
 for(MP42Track *t in file.tracks){[t setValue:source forKey:@"URL"];} // Relink the replacement file: it has a new filesystem identity.
 [fm removeItemAtURL:dest error:NULL];error=nil;
 BOOL retried=[file writeToUrl:dest options:@{} error:&error]; if(!retried)NSLog(@"Retry: %@ sourceURL=%@",error,file.tracks.firstObject.URL);
 check(retried,"retry after relinking restored source succeeds");
 MP42File *loaded=[[MP42File alloc]initWithURL:dest error:&error];check(loaded.tracks.count==1,"retry retains requested track");
 NSURL *edit=[dir URLByAppendingPathComponent:@"edit.m4a"];[fm removeItemAtURL:edit error:NULL];[fm copyItemAtURL:[NSURL fileURLWithPath:@(argv[1])] toURL:edit error:NULL];
 loaded=[[MP42File alloc]initWithURL:edit error:&error];
 if(loaded.tracks.count){MP42Track *t=loaded.tracks.firstObject;object_setClass(t,FailingAudioTrack.class);t.name=@"Trigger edited property";
 error=nil;BOOL updated=[loaded updateMP4FileWithOptions:@{} error:&error];
 check(!updated && [error.domain isEqual:@"InjectedTrackWriteFailure"],"track write failure propagates original error");}
 NSURL *invalidDest=[dir URLByAppendingPathComponent:@"bad-setup.mp4"];[fm removeItemAtURL:invalidDest error:NULL];
 MP42File *invalidFile=[[MP42File alloc]init];MP42VideoTrack *invalidTrack=[[MP42VideoTrack alloc]init];
 MP42FileImporter *partialImporter=[[MP42FileImporter alloc]initWithURL:source error:&error];
 MP42Track *partialTrack=partialImporter.tracks.firstObject;
 partialTrack.conversionSettings=[MP42AudioConversionSettings audioConversionWithBitRate:96 mixDown:kMP42AudioMixdown_Stereo drc:0];
 [invalidFile addTrack:partialTrack];
 InvalidVideoImporter *invalidImporter=[[InvalidVideoImporter alloc]init];
 [invalidTrack setValue:@(kMP42VideoCodecType_H264) forKey:@"format"];
 [invalidTrack setValue:invalidImporter forKey:@"importer"];[invalidFile addTrack:invalidTrack];
 observedTrack=partialTrack;sawInitializedConverter=NO;
 error=nil;BOOL invalidSaved=[invalidFile writeToUrl:invalidDest options:@{} error:&error];
 check(sawInitializedConverter,"valid audio converter was initialized before later setup failure");
 check(!invalidSaved && error!=nil,"partial codec setup returns failure without hanging");
 check([partialTrack valueForKey:@"converter"]==nil,"partial setup cancels and releases initialized converter");
 [invalidFile removeTracks:@[invalidTrack]];
 [fm removeItemAtURL:invalidDest error:NULL];error=nil;
 check([invalidFile writeToUrl:invalidDest options:@{} error:&error],"retry after setup failure succeeds");
 loaded=[[MP42File alloc]initWithURL:invalidDest error:&error];
 check(loaded.tracks.count==1,"setup retry retains valid audio track");
 }return failures?1:0;}
