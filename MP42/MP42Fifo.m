//
//  MP42Fifo.m
//  Subler
//
//  Created by Damiano Galassi on 09/08/13.
//

#import "MP42Fifo.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Fifo {
    id *_array;
    NSUInteger _head;
    NSUInteger _tail;
    NSUInteger _size;
    NSUInteger _count;
    BOOL _cancelled;
    NSCondition *_condition;
}

- (instancetype)init {
    return [self initWithCapacity:300];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    NSParameterAssert(capacity >= 2);
    self = [super init];
    if (self) {
        // Preserve the existing ring's usable capacity (one reserved slot).
        _size = capacity;
        _array = calloc(_size, sizeof(id));
        if (!_array) { [self release]; return nil; }
        _condition = [[NSCondition alloc] init];
    }
    return self;
}

- (void)enqueue:(id)item {
    NSParameterAssert(item != nil);
    [_condition lock];
    while (_count == _size - 1 && !_cancelled) {
        [_condition wait];
    }
    if (!_cancelled) {
        _array[_tail] = [item retain];
        _tail = (_tail + 1) % _size;
        _count++;
        [_condition broadcast];
    }
    [_condition unlock];
}

// Caller holds the condition lock. Transfer the ring's retained reference.
- (nullable id)removeFirstItem NS_RETURNS_RETAINED {
    if (!_count) { return nil; }
    id item = _array[_head];
    _array[_head] = nil;
    _head = (_head + 1) % _size;
    _count--;
    [_condition broadcast];
    return item;
}

- (nullable id)dequeue NS_RETURNS_RETAINED {
    [_condition lock];
    id item = [self removeFirstItem];
    [_condition unlock];
    return item;
}

- (nullable id)dequeueAndWait NS_RETURNS_RETAINED {
    [_condition lock];
    while (!_count && !_cancelled) {
        [_condition wait];
    }
    id item = _cancelled ? nil : [self removeFirstItem];
    [_condition unlock];
    return item;
}

- (NSUInteger)count {
    [_condition lock];
    NSUInteger count = _count;
    [_condition unlock];
    return count;
}

- (BOOL)isFull {
    return self.count >= _size - 1;
}

- (BOOL)isEmpty {
    return self.count == 0;
}

- (void)drain {
    id item;
    while ((item = [self dequeue])) { [item release]; }
}

- (void)cancel {
    [_condition lock];
    _cancelled = YES;
    [_condition broadcast];
    [_condition unlock];
    [self drain];
}

- (void)dealloc {
    [self drain];
    free(_array);
    [_condition release];
    [super dealloc];
}

@end
