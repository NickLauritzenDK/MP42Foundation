#import <AppKit/AppKit.h>
#import <MP42Foundation/MP42Foundation.h>
static NSDictionary *summary(MP42File *file) {
    NSMutableArray *tracks=[NSMutableArray array];
    for (MP42Track *track in file.tracks) {
        NSMutableDictionary *d=[@{@"type":@(track.mediaType),@"format":@(track.format),@"language":track.language?:@"",@"name":track.name?:@"",@"duration":@(track.duration),@"timescale":@(track.timescale)} mutableCopy];
        if ([track isKindOfClass:MP42VideoTrack.class]) { MP42VideoTrack *v=(id)track;d[@"width"]=@(v.width);d[@"height"]=@(v.height); }
        if ([track isKindOfClass:MP42AudioTrack.class]) d[@"channels"]=@(((MP42AudioTrack*)track).channels);
        [tracks addObject:d];
    }
    NSMutableDictionary *metadata=[NSMutableDictionary dictionary];
    for (MP42MetadataItem *item in file.metadata.items) if (item.stringValue) metadata[item.identifier]=item.stringValue;
    NSMutableArray *chapters=[NSMutableArray array];
    MP42ChapterTrack *chapterTrack=nil;
    for(MP42Track *track in file.tracks) if([track isKindOfClass:MP42ChapterTrack.class]) {chapterTrack=(id)track;break;}
    for (MP42TextSample *c in chapterTrack.chapters) [chapters addObject:@{@"title":c.title?:@"",@"timestamp":@(c.timestamp)}];
    return @{@"tracks":tracks,@"metadata":metadata,@"chapters":chapters};
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc<4)return 2;
    NSError *error=nil;
    NSString *mode=@(argv[1]);
    NSURL *input=[NSURL fileURLWithPath:@(argv[2])];
    MP42File *file=[[MP42File alloc]init];
    if([mode isEqualToString:@"inventory"]) {
        MP42FileImporter *importer=[[MP42FileImporter alloc]initWithURL:input error:&error];
        if(!importer){NSLog(@"%@",error);return 3;}
        file=(id)importer;
    } else {
        MP42FileImporter *importer=[[MP42FileImporter alloc]initWithURL:input error:&error];
        if(!importer){NSLog(@"%@",error);return 3;}
        for(MP42Track *t in importer.tracks) {
            if(t.format==kMP42SubtitleCodecType_PGS || t.format==kMP42SubtitleCodecType_VobSub)
                t.conversionSettings=[MP42ConversionSettings subtitlesConversion];
            if([mode isEqualToString:@"convert"] && [t isKindOfClass:MP42AudioTrack.class])
                t.conversionSettings=[MP42AudioConversionSettings audioConversionWithBitRate:96 mixDown:kMP42AudioMixdown_Stereo drc:0];
            if([mode isEqualToString:@"ac3"] && [t isKindOfClass:MP42AudioTrack.class])
                t.conversionSettings=[[MP42AudioConversionSettings alloc]initWithFormat:kMP42AudioCodecType_AC3 bitRate:96 mixDown:kMP42AudioMixdown_Stereo drc:0];
            [file addTrack:t];
        }
        if(argc>4) {
            MP42FileImporter *subs=[[MP42FileImporter alloc]initWithURL:[NSURL fileURLWithPath:@(argv[4])] error:&error];
            if(!subs)return 4;
            for(MP42Track *t in subs.tracks){t.language=@"en";[file addTrack:t];}
        }
        MP42ChapterTrack *chapters=[[MP42ChapterTrack alloc]init];
        [chapters addChapter:@"Start" timestamp:0];[chapters addChapter:@"Second" timestamp:1000];[file addTrack:chapters];
        [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyName value:@"Regression æøå" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:nil]];
        [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyDirector value:@"Director Test" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:nil]];
        NSURL *out=[NSURL fileURLWithPath:@(argv[3])];
        if(![file writeToUrl:out options:@{} error:&error]){NSLog(@"WRITE %@",error);return 5;}
        file=[[MP42File alloc]initWithURL:out error:&error];
        if(!file){NSLog(@"READ %@",error);return 6;}
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:summary(file) options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if(!json)return 7;
    if([mode isEqualToString:@"inventory"]) [json writeToFile:@(argv[3]) atomically:YES];
    else [json writeToFile:[@(argv[3]) stringByAppendingString:@".json"] atomically:YES];
    puts("PASS: media probe");
}return 0;}
