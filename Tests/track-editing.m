#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Foundation.h>
// Declare the release APIs locally so the unrepaired framework can be tested
// for their absence at runtime, rather than failing to compile this harness.
@interface MP42File (ReleaseTrackAPI)
- (void)insertTrack:(MP42Track *)track atIndex:(NSUInteger)index;
- (void)moveTracksAtIndexes:(NSArray<NSNumber *> *)indexes toIndexes:(NSArray<NSNumber *> *)destIndexes;
@end
static NSDictionary *snapshot(MP42File *file, NSArray<MP42AudioTrack *> *original) {
    NSMutableArray *links = [NSMutableArray array];
    for (MP42AudioTrack *t in original) {
        [links addObject:@{ @"name":t.name, @"fallback":t.fallbackTrack.name ?: @"", @"follows":t.followsTrack.name ?: @"" }];
    }
    return @{@"order":[file.tracks valueForKey:@"name"], @"links":links,
             @"canUndo":@(file.undo.canUndo), @"canRedo":@(file.undo.canRedo)};
}
static void runCase(NSMutableDictionary *results, NSString *key, NSString *operation, NSArray<NSNumber *> *selection, NSUInteger destination) {
    MP42File *file = [[MP42File alloc] init];
    NSMutableArray<MP42AudioTrack *> *tracks = [NSMutableArray array];
    for (NSString *name in @[@"A",@"B",@"C",@"D",@"E"]) {
        MP42AudioTrack *t = [[MP42AudioTrack alloc] init]; t.name = name;
        [tracks addObject:t]; [file addTrack:t];
    }
    tracks[0].fallbackTrack = tracks[1]; tracks[4].followsTrack = tracks[2];
    NSUndoManager *undo = [[NSUndoManager alloc] init]; undo.groupsByEvent = NO; file.undo = undo;
    NSMutableArray *states = [NSMutableArray arrayWithObject:snapshot(file, tracks)];
    @try {
        [undo beginUndoGrouping];
        if ([operation isEqualToString:@"insert"]) {
            MP42AudioTrack *t = [[MP42AudioTrack alloc] init]; t.name = @"N";
            [file insertTrack:t atIndex:destination];
        } else {
            NSMutableArray *chosen = [NSMutableArray array];
            for (NSNumber *n in selection) [chosen addObject:tracks[n.unsignedIntegerValue]];
            if ([operation isEqualToString:@"remove"]) [file removeTracks:chosen];
            else [file moveTracks:chosen toIndex:destination];
        }
        [undo endUndoGrouping]; [states addObject:snapshot(file,tracks)];
        for (int repeat=0; repeat<2; repeat++) {
            if (undo.canUndo) [undo undo]; [states addObject:snapshot(file,tracks)];
            if (undo.canRedo) [undo redo]; [states addObject:snapshot(file,tracks)];
        }
        results[key] = states;
    } @catch (NSException *exception) {
        results[key] = @{@"exception":exception.name, @"states":states};
    }
}
int main(void) { @autoreleasepool {
    MP42File *probe = [[MP42File alloc] init];
    if (![probe respondsToSelector:@selector(insertTrack:atIndex:)] ||
        ![probe respondsToSelector:@selector(moveTracksAtIndexes:toIndexes:)]) {
        fprintf(stderr,"FAIL: MP42Foundation lacks official 1.9.5 indexed track editing APIs\n"); return 1;
    }
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (NSUInteger i=0;i<=5;i++) runCase(results,[NSString stringWithFormat:@"insert-%lu",(unsigned long)i],@"insert",@[],i);
    for (NSUInteger mask=1;mask<32;mask++) {
        NSMutableArray *selection = [NSMutableArray array];
        for (NSUInteger i=0;i<5;i++) if (mask & (1<<i)) [selection addObject:@(i)];
        for (NSUInteger reverse=0;reverse<2;reverse++) {
            NSArray *chosen = reverse ? selection.reverseObjectEnumerator.allObjects : selection;
            runCase(results,[NSString stringWithFormat:@"remove-%lu-%lu",(unsigned long)mask,(unsigned long)reverse],@"remove",chosen,0);
            for (NSUInteger destination=0;destination<=5;destination++) {
                runCase(results,[NSString stringWithFormat:@"move-%lu-%lu-%lu",(unsigned long)mask,(unsigned long)reverse,(unsigned long)destination],@"move",chosen,destination);
            }
        }
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if (!data) { fprintf(stderr,"JSON failure\n"); return 1; }
    fwrite(data.bytes,1,data.length,stdout); putchar('\n');
} return 0; }
