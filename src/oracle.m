// oracle: passive measurement of the user's desktop state during agent actions.
// Records frontmost app, system-wide focused element (if Accessibility is granted),
// pointer position/jumps, pointer presence on the hidden display, HID idle time,
// and windows that appear on the visible (main) display. No event taps. No input.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <signal.h>
static FILE *out; static double hz=50; static CGRect virt={{NAN,NAN},{0,0}}; static BOOL stop=NO;
static NSDictionary *lastFocus; static NSMutableDictionary *seen; static CGPoint lastMouse; static BOOL haveMouse=NO;
static int frontChanges=0,focusChanges=0,jumps=0,mainAppear=0,virtEntries=0; static pid_t lastFront=0; static BOOL trusted=NO;
typedef AXError(*WinFn)(AXUIElementRef,CGWindowID*); static WinFn axWin;
static void emit(NSDictionary *d){NSData *j=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];fwrite(j.bytes,1,j.length,out);fputc('\n',out);fflush(out);}
static double now(void){return [NSDate date].timeIntervalSince1970;}
static id axv(AXUIElementRef e,CFStringRef k){CFTypeRef v=NULL;if(!e)return nil;AXUIElementCopyAttributeValue(e,k,&v);return v?CFBridgingRelease(v):nil;}
static NSDictionary *focusState(void){
 if(!trusted)return @{@"ax":@"untrusted"};
 AXUIElementRef sys=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(sys,.2);CFTypeRef el=NULL;AXError e=AXUIElementCopyAttributeValue(sys,kAXFocusedUIElementAttribute,&el);CFRelease(sys);
 if(e||!el)return @{@"ax":@"none",@"err":@(e)};
 pid_t p=0;AXUIElementGetPid((AXUIElementRef)el,&p);id role=axv((AXUIElementRef)el,kAXRoleAttribute);id ident=axv((AXUIElementRef)el,CFSTR("AXIdentifier"));id title=axv((AXUIElementRef)el,kAXTitleAttribute);
 id win=axv((AXUIElementRef)el,kAXWindowAttribute);CGWindowID wid=0;if(win&&axWin)axWin((__bridge AXUIElementRef)win,&wid);id wtitle=win?axv((__bridge AXUIElementRef)win,kAXTitleAttribute):nil;
 CFRelease(el);
 return @{@"pid":@(p),@"role":[role isKindOfClass:NSString.class]?role:@"",@"id":[ident isKindOfClass:NSString.class]?ident:@"",@"title":[title isKindOfClass:NSString.class]?title:@"",@"wid":@(wid),@"wtitle":[wtitle isKindOfClass:NSString.class]?wtitle:@""};
}
static void tick(void){
 double t=now();NSMutableDictionary *ev=[NSMutableDictionary new];ev[@"t"]=@(t);BOOL changed=NO;
 NSRunningApplication *f=NSWorkspace.sharedWorkspace.frontmostApplication;if(f.processIdentifier!=lastFront){if(lastFront)frontChanges++;lastFront=f.processIdentifier;ev[@"front"]=@{@"pid":@(f.processIdentifier),@"name":f.localizedName?:@""};changed=YES;}
 NSDictionary *fs=focusState();static int focusFail=0;if(fs[@"ax"]&&[fs[@"ax"] isEqual:@"none"]){focusFail++;}else if(![fs isEqual:lastFocus]){if(lastFocus)focusChanges++;lastFocus=fs;ev[@"focus"]=fs;changed=YES;}
 CGEventRef e=CGEventCreate(NULL);CGPoint m=CGEventGetLocation(e);CFRelease(e);
 if(haveMouse){double d=hypot(m.x-lastMouse.x,m.y-lastMouse.y);if(d>150){jumps++;ev[@"mouse_jump"]=@{@"from":@[@(lastMouse.x),@(lastMouse.y)],@"to":@[@(m.x),@(m.y)],@"dist":@(d)};changed=YES;}}
 if(!isnan(virt.origin.x)){BOOL in=CGRectContainsPoint(virt,m);static BOOL wasIn=NO;if(in&&!wasIn){virtEntries++;ev[@"mouse_entered_hidden_display"]=@[@(m.x),@(m.y)];changed=YES;}wasIn=in;}
 lastMouse=m;haveMouse=YES;
 NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));NSMutableSet *cur=[NSMutableSet new];NSMutableArray *appeared=[NSMutableArray new];
 CGRect main=CGDisplayBounds(CGMainDisplayID());
 for(NSDictionary *w in all){NSNumber *wid=w[(id)kCGWindowNumber];[cur addObject:wid];if(seen[wid])continue;CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);
  NSDictionary *rec=@{@"wid":wid,@"pid":w[(id)kCGWindowOwnerPID]?:@0,@"owner":w[(id)kCGWindowOwnerName]?:@"",@"name":w[(id)kCGWindowName]?:@"",@"layer":w[(id)kCGWindowLayer]?:@0,@"bounds":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)],@"on_main":@(CGRectIntersectsRect(b,main)),@"on_hidden":@(!isnan(virt.origin.x)&&CGRectIntersectsRect(b,virt))};
  seen[wid]=rec;if(CGRectIntersectsRect(b,main)&&b.size.width>=2&&b.size.height>=2){mainAppear++;[appeared addObject:rec];}else if(!isnan(virt.origin.x)&&CGRectIntersectsRect(b,virt)){[appeared addObject:rec];}}
 for(NSNumber *k in [seen.allKeys copy])if(![cur containsObject:k]){[seen removeObjectForKey:k];}
 if(appeared.count){ev[@"windows_appeared"]=appeared;changed=YES;}
 static double lastBeat=0;if(changed||t-lastBeat>1){if(!changed)ev[@"beat"]=@YES;ev[@"hid_idle"]=@(CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,kCGAnyInputEventType));ev[@"mouse"]=@[@(m.x),@(m.y)];emit(ev);lastBeat=t;}
}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<2){fprintf(stderr,"usage: oracle OUT.jsonl [--hz N] [--hidden X,Y,W,H] [--stopfile PATH]\n");return 2;}
 out=fopen(argv[1],"w");if(!out)return 3;NSString *stopfile=nil;
 for(int i=2;i<argc;i++){if(!strcmp(argv[i],"--hz")&&i+1<argc)hz=atof(argv[++i]);else if(!strcmp(argv[i],"--hidden")&&i+1<argc){double v[4];if(sscanf(argv[++i],"%lf,%lf,%lf,%lf",v,v+1,v+2,v+3)==4)virt=CGRectMake(v[0],v[1],v[2],v[3]);}else if(!strcmp(argv[i],"--stopfile")&&i+1<argc)stopfile=@(argv[++i]);}
 if(isnan(virt.origin.x)){CGDirectDisplayID ids[16];uint32_t n=0;CGGetActiveDisplayList(16,ids,&n);for(uint32_t i=0;i<n;i++)if(ids[i]!=CGMainDisplayID()){virt=CGDisplayBounds(ids[i]);break;}}
 trusted=AXIsProcessTrusted();axWin=(WinFn)dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");seen=[NSMutableDictionary new];
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 // Prime the window set without reporting existing windows.
 NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));for(NSDictionary *w in all)seen[w[(id)kCGWindowNumber]]=w;
 emit(@{@"start":@(now()),@"ax_trusted":@(trusted),@"hz":@(hz),@"hidden_display":isnan(virt.origin.x)?@"none":@[@(virt.origin.x),@(virt.origin.y),@(virt.size.width),@(virt.size.height)],@"main_display":@[@(CGDisplayBounds(CGMainDisplayID()).size.width),@(CGDisplayBounds(CGMainDisplayID()).size.height)],@"pid":@(getpid())});
 signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
 dispatch_source_t s1=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());dispatch_source_set_event_handler(s1,^{stop=YES;});dispatch_resume(s1);
 dispatch_source_t s2=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());dispatch_source_set_event_handler(s2,^{stop=YES;});dispatch_resume(s2);
 [NSTimer scheduledTimerWithTimeInterval:1.0/hz repeats:YES block:^(NSTimer *t){tick();if(stopfile&&[[NSFileManager defaultManager] fileExistsAtPath:stopfile])stop=YES;if(stop){emit(@{@"summary":@{@"front_changes":@(frontChanges),@"focus_changes":@(focusChanges),@"mouse_jumps_over_150px":@(jumps),@"windows_appeared_on_main":@(mainAppear),@"mouse_entered_hidden_display":@(virtEntries),@"ax_trusted":@(trusted)}});fclose(out);exit(0);}}];
 [NSApp run];
}return 0;}
