// activator: EXTERNAL attempts to activate / focus a target (pid,wid) using public and private calls.
// Each attempt records the frontmost app afterwards; if the target became frontmost, the previous app
// is re-activated (a restore, logged as failure of prevention).
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
typedef struct{uint32_t hi,lo;}PSN;
static NSMutableArray *rows;static NSRunningApplication *prev;static pid_t pid;static NSString *outPath;
static double now(void){return [NSDate date].timeIntervalSince1970;}
static void spin(double s){[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];}
static void record(NSString *step,double t0,int rc){NSRunningApplication *f=NSWorkspace.sharedWorkspace.frontmostApplication;BOOL stole=f.processIdentifier==pid;NSMutableDictionary *d=[@{@"t_start":@(t0),@"t_end":@(now()),@"step":step,@"rc":@(rc),@"front_after":f.localizedName?:@"",@"front_pid_after":@(f.processIdentifier),@"stole_front":@(stole)} mutableCopy];
 if(stole){[prev activateWithOptions:0];spin(.8);d[@"restored_front"]=NSWorkspace.sharedWorkspace.frontmostApplication.localizedName?:@"";}
 [rows addObject:d];[[NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil] writeToFile:outPath atomically:YES];fprintf(stderr,"%s rc=%d -> front=%s stole=%d\n",step.UTF8String,rc,f.localizedName.UTF8String,stole);}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<4){fprintf(stderr,"usage: activator PID WID OUT.json\n");return 2;}pid=atoi(argv[1]);uint32_t wid=atoi(argv[2]);outPath=@(argv[3]);rows=[NSMutableArray new];
 NSRunningApplication *target=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];if(![target.localizedName isEqual:@"activation-lab"]){fprintf(stderr,"refusing: target is not the disposable fixture\n");return 3;}
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];prev=NSWorkspace.sharedWorkspace.frontmostApplication;
 void *sl=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
 int(*cidf)(void)=dlsym(sl,"SLSMainConnectionID");CGError(*owner)(int,uint32_t,int*)=dlsym(sl,"SLSGetWindowOwner");CGError(*psnFor)(int,PSN*)=dlsym(sl,"SLSGetConnectionPSN");
 CGError(*setFront)(PSN*,uint32_t,uint32_t)=dlsym(sl,"_SLPSSetFrontProcessWithOptions");CGError(*setFront2)(PSN*,uint32_t,uint32_t)=dlsym(sl,"SLPSSetFrontProcessWithOptions");CGError(*post)(PSN*,uint8_t*)=dlsym(sl,"SLPSPostEventRecordTo");CGError(*getFront)(PSN*)=dlsym(sl,"SLPSGetFrontProcess");
 int tcid=0;PSN tpsn={0},ppsn={0};if(owner(cidf(),wid,&tcid)||psnFor(tcid,&tpsn)){fprintf(stderr,"cannot resolve target psn\n");return 4;}getFront(&ppsn);
 double t;int rc;
 // B1 public: NSRunningApplication activateWithOptions (from another process)
 t=now();BOOL ok=[target activateWithOptions:0];spin(1.2);record(@"B1 NSRunningApplication activateWithOptions:0 (external)",t,ok?0:1);
 t=now();ok=[target activateWithOptions:NSApplicationActivateIgnoringOtherApps];spin(1.2);record(@"B2 NSRunningApplication activateWithOptions:IgnoringOtherApps (external)",t,ok?0:1);
 // B3 AX: set AXFrontmost on the app element
 t=now();AXUIElementRef app=AXUIElementCreateApplication(pid);rc=AXUIElementSetAttributeValue(app,kAXFrontmostAttribute,kCFBooleanTrue);spin(1.2);record(@"B3 AX kAXFrontmost=true on app element",t,rc);
 // B4 AX: AXRaise on the window
 t=now();id ws=nil;{CFTypeRef v=NULL;AXUIElementCopyAttributeValue(app,kAXWindowsAttribute,&v);ws=v?CFBridgingRelease(v):nil;}rc=-1;typedef AXError(*WinFn)(AXUIElementRef,CGWindowID*);WinFn axWin=(WinFn)dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");for(id w in ws){CGWindowID n=0;if(axWin((__bridge AXUIElementRef)w,&n)==0&&n==wid)rc=AXUIElementPerformAction((__bridge AXUIElementRef)w,kAXRaiseAction);}spin(1.2);record(@"B4 AX AXRaise on exact window",t,rc);
 // B5 private: _SLPSSetFrontProcessWithOptions with kCPSUserGenerated (0x200)
 t=now();rc=setFront?setFront(&tpsn,wid,0x200):-999;spin(1.2);record(@"B5 _SLPSSetFrontProcessWithOptions kCPSUserGenerated",t,rc);
 // B6 private: kCPSNoWindows (0x400) — activate app without bringing windows forward
 t=now();rc=setFront2?setFront2(&tpsn,wid,0x400):-999;spin(1.2);record(@"B6 SLPSSetFrontProcessWithOptions kCPSNoWindows",t,rc);
 // B7 private: app-active event record (type 0x0D, state 1) to target only (cua-driver 'focus flip' half)
 t=now();uint8_t b[0xf8]={0};b[4]=0xf8;b[8]=0x0d;b[0x8a]=1;memcpy(b+0x3c,&wid,4);rc=post(&tpsn,b);spin(1.2);record(@"B7 SLPSPostEventRecordTo app-active record to target only",t,rc);
 // B8 private: yabai/cua pair — deactivate record to the USER'S front app, activate record to target; then reverse
 t=now();getFront(&ppsn);uint8_t d[0xf8]={0};d[4]=0xf8;d[8]=0x0d;d[0x8a]=2;memcpy(d+0x3c,&wid,4);int r1=post(&ppsn,d);int r2=post(&tpsn,b);spin(1.5);record(@"B8 pair: deactivate-record to user's front app + activate-record to target",t,r1*100+r2);
 t=now();uint8_t e[0xf8]={0};e[4]=0xf8;e[8]=0x0d;e[0x8a]=2;memcpy(e+0x3c,&wid,4);post(&tpsn,e);uint8_t g[0xf8]={0};g[4]=0xf8;g[8]=0x0d;g[0x8a]=1;post(&ppsn,g);spin(1.0);record(@"B8r reverse pair (deactivate target, activate user's app)",t,0);
 // B9 private: yabai make-key-window synthetic click records to target
 t=now();uint8_t k1[0xf8]={0};k1[4]=0xf8;k1[8]=1;k1[0x3a]=0x10;memcpy(k1+0x3c,&wid,4);memset(k1+0x20,0xff,0x10);uint8_t k2[0xf8];memcpy(k2,k1,0xf8);k2[8]=2;r1=post(&tpsn,k1);r2=post(&tpsn,k2);spin(1.2);record(@"B9 synthetic mouse-down/up records to target window",t,r1*100+r2);
 CFRelease(app);return 0;
}}
