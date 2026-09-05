#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
typedef int(*fn_cid)(void);typedef CGError(*fn_owner)(int,uint32_t,int*);typedef CGError(*fn_seta)(int,uint32_t,float);typedef CGError(*fn_geta)(int,uint32_t,float*);
int main(int argc,const char**argv){@autoreleasepool{
 uint32_t wid=atoi(argv[1]);void*SL=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
 fn_cid CID=(fn_cid)dlsym(SL,"SLSMainConnectionID");fn_owner OWN=(fn_owner)dlsym(SL,"SLSGetWindowOwner");fn_seta SETA=(fn_seta)dlsym(SL,"SLSSetWindowAlpha");fn_geta GETA=(fn_geta)dlsym(SL,"SLSGetWindowAlpha");
 int mine=CID();int owner=0;OWN(mine,wid,&owner);float a0=-1,a1=-1;if(GETA)GETA(mine,wid,&a0);
 CGError e=SETA?SETA(mine,wid,0.0f):-999;usleep(80000);if(GETA)GETA(mine,wid,&a1);
 printf("{\"wid\":%u,\"owner_cid\":%d,\"my_cid\":%d,\"external\":%s,\"set_err\":%d,\"alpha_before\":%.2f,\"alpha_after\":%.2f,\"took_effect\":%s}\n",wid,owner,mine,owner!=mine?"true":"false",e,a0,a1,(a1>=0&&a1<0.5)?"true":"false");
}return 0;}
