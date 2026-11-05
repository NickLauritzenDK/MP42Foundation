#import <Foundation/Foundation.h>
#import "MP42Fifo.h"
static BOOL finished(dispatch_semaphore_t sem){return dispatch_semaphore_wait(sem,dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC))==0;}
int main(void){@autoreleasepool{
 int failures=0;
 MP42Fifo *empty=[[MP42Fifo alloc]initWithCapacity:2];dispatch_semaphore_t done=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(0,0),^{id item=[empty dequeueAndWait];[item release];dispatch_semaphore_signal(done);});
 BOOL blocked=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0;
 [empty cancel];BOOL ok=blocked && finished(done);printf("%s: cancelled empty reader returns\n",ok?"PASS":"FAIL");if(!ok)failures++;
 MP42Fifo *full=[[MP42Fifo alloc]initWithCapacity:2];[full enqueue:@1];dispatch_semaphore_t writer=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(0,0),^{[full enqueue:@2];dispatch_semaphore_signal(writer);});
 blocked=dispatch_semaphore_wait(writer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0;
 [full cancel];ok=blocked && finished(writer);printf("%s: cancelled writer returns without adding data\n",ok && [full isEmpty]?"PASS":"FAIL");if(!ok || ![full isEmpty])failures++;
 [full enqueue:@3];id rejected=[full dequeue];ok=rejected==nil;[rejected release];printf("%s: cancelled queue rejects later data\n",ok?"PASS":"FAIL");if(!ok)failures++;
 MP42Fifo *normal=[[MP42Fifo alloc]initWithCapacity:3];[normal enqueue:@1];[normal enqueue:@2];id a=[normal dequeue],b=[normal dequeueAndWait];ok=[a isEqual:@1] && [b isEqual:@2] && [normal isEmpty];[a release];[b release];printf("%s: normal ordering and ownership\n",ok?"PASS":"FAIL");if(!ok)failures++;
 MP42Fifo *shared=[[MP42Fifo alloc]initWithCapacity:8];dispatch_group_t group=dispatch_group_create();NSMutableIndexSet *seen=[NSMutableIndexSet indexSet];
 for(int p=0;p<2;p++){dispatch_group_async(group,dispatch_get_global_queue(0,0),^{for(int i=0;i<1000;i++){[shared enqueue:@(p*1000+i)];}});}
 for(int c=0;c<2;c++){dispatch_group_async(group,dispatch_get_global_queue(0,0),^{for(int i=0;i<1000;i++){NSNumber *n=[shared dequeueAndWait];@synchronized(seen){[seen addIndex:n.unsignedIntegerValue];}[n release];}});}
 ok=dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0 && seen.count==2000 && [shared isEmpty];printf("%s: concurrent producers/readers lose no items\n",ok?"PASS":"FAIL");if(!ok)failures++;
 MP42Fifo *readers=[[MP42Fifo alloc]initWithCapacity:2];dispatch_group_t waiting=dispatch_group_create();
 for(int i=0;i<3;i++){dispatch_group_async(waiting,dispatch_get_global_queue(0,0),^{id n=[readers dequeueAndWait];[n release];});}
 [readers cancel];ok=dispatch_group_wait(waiting,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0;printf("%s: cancellation wakes all readers\n",ok?"PASS":"FAIL");if(!ok)failures++;
 // Failed old readers intentionally remain blocked until process exits.
 return failures?1:0;
}}
