#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Foundation.h>
@interface MP42Track (StateSetup)
@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;
@property(nonatomic, readwrite) BOOL muxed;
@property(nonatomic, readwrite, getter=isEdited) BOOL edited;
@end
static NSDictionary *snapshot(MP42File *file, NSArray<MP42Track *> *tracked) {
    NSMutableArray *states = [NSMutableArray array];
    for (MP42Track *t in tracked) {
        [states addObject:@{@"name":t.name, @"id":@(t.trackId), @"source":@(t.sourceId),
                           @"muxed":@(t.muxed), @"edited":@(t.edited)}];
    }
    return @{@"order":[file.tracks valueForKey:@"name"], @"states":states,
             @"undo":@(file.undo.canUndo), @"redo":@(file.undo.canRedo)};
}
static NSArray *editingStates(MP42File *file, NSArray *tracked, void (^operation)(void)) {
    NSUndoManager *undo = [[NSUndoManager alloc] init]; undo.groupsByEvent = NO; file.undo = undo;
    NSMutableArray *states = [NSMutableArray arrayWithObject:snapshot(file,tracked)];
    @try {
        [undo beginUndoGrouping]; operation(); [undo endUndoGrouping];
        [states addObject:snapshot(file,tracked)];
        for (int i=0;i<2;i++) {
            if (undo.canUndo) [undo undo]; [states addObject:snapshot(file,tracked)];
            if (undo.canRedo) [undo redo]; [states addObject:snapshot(file,tracked)];
        }
    } @catch (NSException *e) { [states addObject:@{@"exception":e.name}]; }
    return states;
}
static MP42File *makeFile(NSMutableArray *tracks) {
    MP42File *file = [[MP42File alloc] init];
    for (NSString *name in @[@"A",@"B",@"C",@"D",@"E"]) {
        MP42AudioTrack *t = [[MP42AudioTrack alloc] init]; t.name = name;
        [file addTrack:t]; [tracks addObject:t];
        t.trackId = (MP42TrackId)tracks.count; t.sourceId = t.trackId; t.muxed = YES; t.edited = NO;
    }
    return file;
}
int main(void) { @autoreleasepool {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSArray *mappings = @[@[@[@0,@2],@[@1,@4]], @[@[@2,@0],@[@4,@1]],
                          @[@[@1,@3],@[@3,@1]], @[@[@4,@0],@[@0,@4]], @[@[],@[]]];
    for (NSUInteger i=0;i<mappings.count;i++) {
        NSMutableArray *tracks = [NSMutableArray array]; MP42File *file = makeFile(tracks);
        results[[NSString stringWithFormat:@"indexed-%lu",(unsigned long)i]] = editingStates(file,tracks,^{
            [file moveTracksAtIndexes:mappings[i][0] toIndexes:mappings[i][1]];
        });
    }
    for (NSString *operation in @[@"add",@"insert",@"remove",@"empty-remove",@"empty-move",@"mixed"]) {
        NSMutableArray *tracks = [NSMutableArray array]; MP42File *file = makeFile(tracks);
        MP42AudioTrack *fresh = [[MP42AudioTrack alloc] init]; fresh.name = @"N";
        fresh.trackId = 42; fresh.sourceId = 17; fresh.muxed = YES; fresh.edited = NO;
        [tracks addObject:fresh];
        results[operation] = editingStates(file,tracks,^{
            if ([operation isEqual:@"add"]) [file addTrack:fresh];
            if ([operation isEqual:@"insert"]) [file insertTrack:fresh atIndex:2];
            if ([operation isEqual:@"remove"]) [file removeTracks:@[tracks[1],tracks[3]]];
            if ([operation isEqual:@"empty-remove"]) [file removeTracks:@[]];
            if ([operation isEqual:@"empty-move"]) [file moveTracks:@[] toIndex:0];
            if ([operation isEqual:@"mixed"]) {
                [file insertTrack:fresh atIndex:2]; [file moveTracks:@[tracks[0]] toIndex:6];
                [file removeTracks:@[tracks[2],tracks[3]]];
            }
        });
    }
    for (NSUInteger enabled=0;enabled<2;enabled++) {
        MP42File *file = [[MP42File alloc] init];
        MP42ChapterTrack *first = [[MP42ChapterTrack alloc] init]; first.name = @"old chapters";
        MP42ChapterTrack *second = [[MP42ChapterTrack alloc] init]; second.name = @"new chapters";
        [file addTrack:first];
        if (enabled) results[@"chapter-replacement-undo"] = editingStates(file,@[first,second],^{ [file addTrack:second]; });
        else {
            @try { [file addTrack:second]; results[@"chapter-replacement"] = snapshot(file,@[first,second]); }
            @catch (NSException *e) { results[@"chapter-replacement"] = @{@"exception":e.name}; }
        }
        if (enabled) break;
    }
    MP42ChapterTrack *chapter = [[MP42ChapterTrack alloc] init];
    [chapter addChapter:@"B" timestamp:1000]; [chapter addChapter:@"A" timestamp:0]; [chapter addChapter:@"C" timestamp:1000];
    NSUndoManager *undo = [[NSUndoManager alloc] init]; undo.groupsByEvent=NO; chapter.undo=undo;
    NSMutableArray *chapters = [NSMutableArray array];
    [chapters addObject:[chapter.chapters valueForKey:@"title"]];
    [undo beginUndoGrouping]; [chapter removeChaptersAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,2)]]; [undo endUndoGrouping];
    [chapters addObject:[chapter.chapters valueForKey:@"title"]];
    [undo undo]; [chapters addObject:[chapter.chapters valueForKey:@"title"]];
    [undo redo]; [chapters addObject:[chapter.chapters valueForKey:@"title"]];
    results[@"chapters"] = chapters;
    NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    fwrite(data.bytes,1,data.length,stdout); putchar('\n');
} return 0; }
