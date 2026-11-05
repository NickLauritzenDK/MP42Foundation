#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <mp4v2.h>
static void require(BOOL ok, NSString *what, NSError *error) {
    if (!ok) { fprintf(stderr,"FAIL: %s: %s\n",what.UTF8String,error.description.UTF8String ?: ""); exit(1); }
}
static NSDictionary *describe(NSURL *url) {
    NSError *error = nil;
    MP42File *file = [[MP42File alloc] initWithURL:url error:&error]; require(file!=nil,@"Reopen MP4",error);
    MP4FileHandle handle = MP4Read(url.fileSystemRepresentation); require(handle!=MP4_INVALID_FILE_HANDLE,@"Read MP4 samples",nil);
    NSMutableArray *tracks = [NSMutableArray array];
    for (MP42Track *track in file.tracks) {
        NSMutableData *payload = [NSMutableData data]; NSMutableArray *timing = [NSMutableArray array];
        uint32_t count = MP4GetTrackNumberOfSamples(handle,track.trackId);
        for (uint32_t i=1;i<=count;i++) {
            uint8_t *bytes=NULL; uint32_t size=0; MP4Timestamp start=0; MP4Duration duration=0; MP4Duration offset=0; bool sync=false;
            require(MP4ReadSample(handle,track.trackId,i,&bytes,&size,&start,&duration,&offset,&sync),@"Read sample",nil);
            [payload appendBytes:bytes length:size]; MP4Free(bytes);
            [timing addObject:@[@(start),@(duration),@(offset),@(size)]];
        }
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(payload.bytes,(CC_LONG)payload.length,digest);
        NSMutableString *hash = [NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [hash appendFormat:@"%02x",digest[i]];
        [tracks addObject:@{@"name":track.name,@"language":track.language,@"format":@(track.format),@"duration":@(track.duration),
            @"timescale":@(track.timescale),@"samples":timing,@"payloadSHA256":hash}];
    }
    MP4Close(handle,0);
    return @{@"tracks":tracks,@"title":[file.metadata metadataItemsFilteredByIdentifier:MP42MetadataKeyName].firstObject.value ?: @"", @"chapters":[file.chapters.chapters valueForKey:@"title"] ?: @[]};
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    require(argc==3,@"Expected fixture and output directory",nil);
    NSURL *input = [NSURL fileURLWithPath:@(argv[1])]; NSURL *directory=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error=nil; MP42File *file=[[MP42File alloc] init];
    NSMutableArray *importers=[NSMutableArray array];
    for (NSString *name in @[@"Dansk æøå",@"English"]) {
        MP42FileImporter *importer=[[MP42FileImporter alloc] initWithURL:input error:&error]; require(importer.tracks.count==1,@"Import AAC",error);
        [importers addObject:importer]; MP42Track *track=importer.tracks.firstObject; track.name=name;
        track.language=[name isEqual:@"English"] ? @"en" : @"da"; [file addTrack:track];
    }
    NSURL *srt=[directory URLByAppendingPathComponent:@"captions.srt"];
    [@"1\n00:00:00,000 --> 00:00:00,200\nPrøve æøå\n\n2\n00:00:00,250 --> 00:00:00,450\nSlut\n" writeToURL:srt atomically:YES encoding:NSUTF8StringEncoding error:&error];
    MP42FileImporter *subtitles=[[MP42FileImporter alloc] initWithURL:srt error:&error]; require(subtitles.tracks.count==1,@"Import SRT",error);
    [importers addObject:subtitles]; [file addTrack:subtitles.tracks.firstObject];
    MP42ChapterTrack *chapters=[[MP42ChapterTrack alloc] init]; [chapters addChapter:@"Start" timestamp:0]; [chapters addChapter:@"Slut" timestamp:250]; [file addTrack:chapters];
    [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyName value:@"Syntetisk prøve æøå" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:nil]];
    NSURL *saved=[directory URLByAppendingPathComponent:@"saved.mp4"];
    [[NSFileManager defaultManager] removeItemAtURL:saved error:NULL];
    require([file writeToUrl:saved options:nil error:&error],@"Save imported tracks",error);
    NSMutableDictionary *results=[NSMutableDictionary dictionary]; results[@"saved"]=describe(saved);
    for (NSString *operation in @[@"remove-undo",@"remove-redo",@"move-undo",@"move-redo"]) {
        MP42File *loaded=[[MP42File alloc] initWithURL:saved error:&error]; require(loaded!=nil,@"Open for editing",error);
        NSUndoManager *undo=[[NSUndoManager alloc] init]; undo.groupsByEvent=NO; loaded.undo=undo;
        [undo beginUndoGrouping];
        if ([operation hasPrefix:@"remove"]) [loaded removeTracks:@[loaded.tracks[0]]];
        else [loaded moveTracks:@[loaded.tracks[0]] toIndex:2];
        [undo endUndoGrouping]; [undo undo]; if ([operation hasSuffix:@"redo"]) [undo redo];
        NSURL *destination=[directory URLByAppendingPathComponent:[operation stringByAppendingPathExtension:@"mp4"]];
        [[NSFileManager defaultManager] removeItemAtURL:destination error:NULL];
        require([loaded writeToUrl:destination options:nil error:&error],@"Save edited MP4",error);
        results[operation]=describe(destination);
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingSortedKeys error:NULL];
    fwrite(data.bytes,1,data.length,stdout); putchar('\n');
} return 0; }
