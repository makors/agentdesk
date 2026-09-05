// agentdesk-daemon: keeps agent-owned dialogs off the user's screen.
// It watches, at high rate, for any NEW top-level window owned by a REGISTERED agent PID that
// appears touching the MAIN display, and immediately relocates it onto the hidden display via
// Accessibility (the only relocation an external process is permitted to perform on a foreign window).
// It never sends keyboard or pointer events and never activates any app.
// Registry: <root>/agents.json = {"pids":[...], "hidden":[x,y,w,h], "margin":N}. Log: <root>/relocations.jsonl
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <signal.h>
typedef AXError(*WinFn)(AXUIElementRef,CGWindowID*);static WinFn axWin;
static NSString *root;static CGRect hidden;static double margin=80;static NSSet *pids;static BOOL stop=NO;
static FILE *gLog;
static id axget(AXUIElementRef e,CFStringRef k){CFTypeRef v=NULL;if(!e||AXUIElementCopyAttributeValue(e,k,&v)!=0||!v)return nil;return CFBridgingRelease(v);}
static AXUIElementRef exactWindow(pid_t pid,CGWindowID wid){AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,1.0);id ws=axget(app,kAXWindowsAttribute);AXUIElementRef hit=NULL;int m=0;for(id w in ([ws isKindOfClass:NSArray.class]?ws:@[])){CGWindowID n=0;if(axWin((__bridge AXUIElementRef)w,&n)==0&&n==wid){hit=(__bridge AXUIElementRef)w;m++;}}if(m==1){CFRetain(hit);}else hit=NULL;CFRelease(app);return hit;}
static void loadRegistry(void){NSData *d=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"agents.json"]];if(!d){pids=[NSSet set];return;}NSDictionary *r=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];pids=[NSSet setWithArray:r[@"pids"]?:@[]];if(r[@"hidden"]){NSArray *h=r[@"hidden"];hidden=CGRectMake([h[0] doubleValue],[h[1] doubleValue],[h[2] doubleValue],[h[3] doubleValue]);}if(r[@"margin"])margin=[r[@"margin"] doubleValue];}
static void relog(NSDictionary *d){NSData *j=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];fwrite(j.bytes,1,j.length,gLog);fputc('\n',gLog);fflush(gLog);}
int main(int argc,const char**argv){@autoreleasepool{
 if(argc<2){fprintf(stderr,"usage: agentdesk-daemon ROOT\n");return 2;}root=@(argv[1]);
 axWin=(WinFn)dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");if(!axWin)return 5;
 if(!AXIsProcessTrusted()){fprintf(stderr,"agentdesk-daemon needs Accessibility\n");return 4;}
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 gLog=fopen([[root stringByAppendingPathComponent:@"relocations.jsonl"] fileSystemRepresentation],"a");
 CGRect mainR=CGDisplayBounds(CGMainDisplayID());hidden=CGRectMake(1512,0,1920,1200);loadRegistry();
 // baseline: remember all current windows per pid so only NEW ones are relocated
 NSMutableSet *known=[NSMutableSet new];NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in all)[known addObject:w[(id)kCGWindowNumber]];
 relog(@{@"event":@"start",@"t":@([NSDate date].timeIntervalSince1970),@"pid":@(getpid()),@"hidden":@[@(hidden.origin.x),@(hidden.origin.y),@(hidden.size.width),@(hidden.size.height)]});
 signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
 dispatch_source_t s1=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());dispatch_source_set_event_handler(s1,^{stop=YES;});dispatch_resume(s1);
 dispatch_source_t s2=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());dispatch_source_set_event_handler(s2,^{stop=YES;});dispatch_resume(s2);
 __block int reloadTick=0;
 [NSTimer scheduledTimerWithTimeInterval:0.002 repeats:YES block:^(NSTimer *t){
  if(stop){relog(@{@"event":@"stop",@"t":@([NSDate date].timeIntervalSince1970)});fclose(gLog);exit(0);}
  if(++reloadTick%100==0)loadRegistry(); // refresh registry ~5x/sec
  NSArray *cur=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));
  for(NSDictionary *w in cur){NSNumber *wid=w[(id)kCGWindowNumber];if([known containsObject:wid])continue;
   pid_t pid=[w[(id)kCGWindowOwnerPID] intValue];int layer=[w[(id)kCGWindowLayer] intValue];
   if(![pids containsObject:@(pid)]||layer!=0){[known addObject:wid];continue;}
   CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);
   if(b.size.width<40||b.size.height<20){continue;} // wait for real geometry, do not mark known yet
   double t_seen=[NSDate date].timeIntervalSince1970;BOOL onMain=CGRectIntersectsRect(b,mainR);
   if(onMain){AXUIElementRef win=exactWindow(pid,[wid unsignedIntValue]);double t_res=[NSDate date].timeIntervalSince1970;
    if(win){CGPoint dst=CGPointMake(hidden.origin.x+margin,hidden.origin.y+margin);AXValueRef v=AXValueCreate(kAXValueCGPointType,&dst);AXError e=AXUIElementSetAttributeValue(win,kAXPositionAttribute,v);CFRelease(v);double t_mv=[NSDate date].timeIntervalSince1970;
     id np=axget(win,kAXPositionAttribute);CGPoint a={0,0};if(np)AXValueGetValue((__bridge AXValueRef)np,kAXValueCGPointType,&a);CFRelease(win);
     relog(@{@"event":@"relocated",@"t":@(t_mv),@"pid":@(pid),@"wid":wid,@"owner":w[(id)kCGWindowOwnerName]?:@"",@"from":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)],@"to":@[@(a.x),@(a.y)],@"ax_error":@(e),@"ms_resolve":@((t_res-t_seen)*1000),@"ms_move":@((t_mv-t_res)*1000),@"ms_on_main":@((t_mv-t_seen)*1000)});
     [known addObject:wid];}
    // if not resolvable yet, leave unknown to retry next tick
   } else {[known addObject:wid];relog(@{@"event":@"appeared_hidden",@"t":@(t_seen),@"pid":@(pid),@"wid":wid,@"owner":w[(id)kCGWindowOwnerName]?:@"",@"bounds":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)]});}
  }
 }];
 [NSApp run];
}return 0;}
