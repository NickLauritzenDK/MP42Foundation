#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Foundation.h>
static int checks = 0;
static void check(BOOL result, NSString *message) {
    if (!result) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
    checks++;
}
int main(void) { @autoreleasepool {
    MP42File *file = [[MP42File alloc] init];
    MP42AudioTrack *a = [[MP42AudioTrack alloc] init];
    MP42AudioTrack *b = [[MP42AudioTrack alloc] init];
    MP42AudioTrack *c = [[MP42AudioTrack alloc] init];
    a.name = @"Dansk æøå"; a.language = @"da";
    [file addTrack:a]; [file addTrack:b]; [file insertTrack:c atIndex:1];
    check([file.tracks isEqualToArray:@[a,c,b]], @"Insertion preserves track order");
    [file moveTracks:@[b] toIndex:0];
    check([file.tracks isEqualToArray:@[b,a,c]], @"Moving tracks preserves identity and order");
    [file removeTracks:@[a]];
    check([file.tracks isEqualToArray:@[b,c]], @"Removing one track retains the others");
    check([a.name isEqualToString:@"Dansk æøå"] && [a.language isEqualToString:@"da"], @"Unicode names and language survive track operations");
    NSUndoManager *trackUndo = [[NSUndoManager alloc] init];
    trackUndo.groupsByEvent = NO; file.undo = trackUndo;
    [trackUndo beginUndoGrouping]; [file removeTracks:@[b]]; [trackUndo endUndoGrouping];
    check([file.tracks isEqualToArray:@[c]] && trackUndo.canUndo, @"Track removal registers undo");
    [trackUndo undo]; check([file.tracks isEqualToArray:@[b,c]], @"Track undo restores original order");
    [trackUndo redo]; check([file.tracks isEqualToArray:@[c]], @"Track redo restores removal");
    MP42ChapterTrack *chapters = [[MP42ChapterTrack alloc] init];
    [chapters addChapter:@"Begyndelse" timestamp:0];
    [chapters addChapter:@"Slutning" timestamp:1000];
    check(chapters.chapterCount == 2, @"Chapter insertion");
    [chapters removeChaptersAtIndexes:[NSIndexSet indexSetWithIndex:0]];
    check(chapters.chapterCount == 1, @"Chapter removal");
    MP42Metadata *metadata = [[MP42Metadata alloc] init];
    MP42MetadataItem *title = [MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyName value:@"Prøve æøå" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:@"da-DK"];
    [metadata addMetadataItem:title];
    check([[metadata metadataItemsFilteredByIdentifier:MP42MetadataKeyName].firstObject.value isEqual:@"Prøve æøå"], @"Unicode metadata round trip");
    check([title.extendedLanguageTag isEqualToString:@"da-DK"], @"Extended metadata language tag");
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    undo.groupsByEvent = NO; metadata.undo = undo;
    [undo beginUndoGrouping]; [metadata removeMetadataItem:title]; [undo endUndoGrouping];
    check(metadata.items.count == 0 && undo.canUndo, @"Metadata removal registers undo");
    [undo undo]; check(metadata.items.count == 1, @"Metadata undo restores item");
    [undo redo]; check(metadata.items.count == 0, @"Metadata redo removes item again");
    printf("PASS: %d baseline behavior checks\n", checks);
} return 0; }
