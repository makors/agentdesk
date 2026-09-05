#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
typedef int (*fn_cid)(void);
typedef CGError (*fn_owner)(int,uint32_t,int*);
typedef CGError (*fn_move)(int,uint32_t,CGPoint*);
typedef CGError (*fn_alpha)(int,uint32_t,float);
typedef CGError (*fn_level)(int,uint32_t,int);
typedef CGError (*fn_order)(int,uint32_t,int,uint32_t);
static CGRect bounds(uint32_t wid){CGRect r=CGRectNull;NSArray *a=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in a)if([w[(id)kCGWindowNumber] unsignedIntValue]==wid)CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&r);return r;}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<4){fprintf(stderr,"usage: foreign-winop PID WID op\n");return 2;}
 pid_t pid=atoi(argv[1]);uint32_t wid=atoi(argv[2]);NSString *op=@(argv[3]);
 void *SL=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
 fn_cid CID=(fn_cid)dlsym(SL,"SLSMainConnectionID");fn_owner OWN=(fn_owner)dlsym(SL,"SLSGetWindowOwner");
 fn_move MV=(fn_move)dlsym(SL,"SLSMoveWindow");fn_alpha AL=(fn_alpha)dlsym(SL,"SLSSetWindowAlpha");fn_level LV=(fn_level)dlsym(SL,"SLSSetWindowLevel");fn_order OR=(fn_order)dlsym(SL,"SLSOrderWindow");
 int mine=CID();int owner=0;CGError oe=OWN?OWN(mine,wid,&owner):-1;
 CGRect before=bounds(wid);CGError e_mine=-999,e_owner=-999;CGPoint dst=CGPointMake(2300,300);
 double t0=[NSDate date].timeIntervalSince1970;
 if([op isEqual:@"move"]&&MV){e_mine=MV(mine,wid,&dst);e_owner=(owner&&owner!=mine)?MV(owner,wid,&dst):e_mine;}
 else if([op isEqual:@"alpha"]&&AL){e_mine=AL(mine,wid,0.0f);e_owner=(owner&&owner!=mine)?AL(owner,wid,0.0f):e_mine;}
 else if([op isEqual:@"level"]&&LV){e_mine=LV(mine,wid,-1);e_owner=(owner&&owner!=mine)?LV(owner,wid,-1):e_mine;}
 else if([op isEqual:@"hide"]&&OR){e_mine=OR(mine,wid,0,0);e_owner=(owner&&owner!=mine)?OR(owner,wid,0,0):e_mine;}
 double dt=([NSDate date].timeIntervalSince1970-t0)*1000;usleep(120000);CGRect after=bounds(wid);
 printf("{\"wid\":%u,\"op\":\"%s\",\"my_cid\":%d,\"owner_cid\":%d,\"owner_err\":%d,\"e_mine\":%d,\"e_owner\":%d,\"call_ms\":%.2f,\"before\":[%.0f,%.0f,%.0f,%.0f],\"after\":[%.0f,%.0f,%.0f,%.0f],\"moved\":%s}\n",
  wid,op.UTF8String,mine,owner,oe,e_mine,e_owner,dt,before.origin.x,before.origin.y,before.size.width,before.size.height,after.origin.x,after.origin.y,after.size.width,after.size.height,(fabs(after.origin.x-before.origin.x)>5||fabs(after.origin.y-before.origin.y)>5||after.size.width<1)?"true":"false");
}return 0;}
