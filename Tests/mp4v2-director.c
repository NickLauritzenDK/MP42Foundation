#include <mp4v2/mp4v2.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
/* Present in Subler's shipped headers/binary but missing from its source pin. */
#ifdef __cplusplus
extern "C"
#endif
bool MP4TagsSetDirector(const MP4Tags *,const char *);
static void require(int ok,const char *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(int argc,char **argv){
    require(argc==2,"Expected synthetic output file");remove(argv[1]);
    MP4FileHandle file=MP4Create(argv[1],0);require(file!=MP4_INVALID_FILE_HANDLE,"Create MP4");
    const MP4Tags *tags=MP4TagsAlloc();require(MP4TagsFetch(tags,file),"Read empty tags");
    require(MP4TagsSetDirector(tags,"Instruktør æøå"),"Set Director metadata");require(MP4TagsStore(tags,file),"Store tags");MP4TagsFree(tags);MP4Close(file,0);
    file=MP4Read(argv[1]);require(file!=MP4_INVALID_FILE_HANDLE,"Reopen MP4");tags=MP4TagsAlloc();require(MP4TagsFetch(tags,file),"Read tags");
    require(tags->director && !strcmp(tags->director,"Instruktør æøå"),"Director Unicode round trip");MP4TagsFree(tags);MP4Close(file,0);
    puts("PASS: Subler-specific MP4v2 Director API persists Unicode metadata");return 0;
}
