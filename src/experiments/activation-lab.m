// activation-lab: disposable REGULAR-policy app on the hidden display that tries every in-process way
// to become active or to show dialogs, and records whether the frontmost app changed. If it becomes
// frontmost it immediately re-activates the previous app (that is a restore, logged as a failure).
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static NSWindow *W; static NSMutableArray *rows; static NSString *outPath; static NSRunningApplication *prev; static NSTextField *tf;
static void spin(double s){NSDate *dl=[NSDate dateWithTimeIntervalSinceNow:s];while([dl timeIntervalSinceNow]>0){NSEvent *e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:dl inMode:NSDefaultRunLoopMode dequeue:YES];if(e)[NSApp sendEvent:e];[NSApp updateWindows];}}
static double now(void){return [NSDate date].timeIntervalSince1970;}
static NSArray *ownCG(void){NSMutableArray *o=[NSMutableArray new];NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in all){if([w[(id)kCGWindowOwnerPID] intValue]!=getpid())continue;CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);if(b.size.width<40)continue;[o addObject:@{@"wid":w[(id)kCGWindowNumber],@"layer":w[(id)kCGWindowLayer],@"cg":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)],@"onscreen":w[(id)kCGWindowIsOnscreen]?:@0,@"on_main":@(CGRectIntersectsRect(b,CGDisplayBounds(CGMainDisplayID())))}];}return o;}
static void save(void){[[NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil] writeToFile:outPath atomically:YES];}
static void record(NSString *step,double t0){
 NSRunningApplication *f=NSWorkspace.sharedWorkspace.frontmostApplication;BOOL stole=(f.processIdentifier==getpid());
 NSMutableDictionary *d=[@{@"t_start":@(t0),@"t_end":@(now()),@"step":step,@"front_after":f.localizedName?:@"",@"front_pid_after":@(f.processIdentifier),@"stole_front":@(stole),@"app_active":@(NSApp.isActive),@"key_window":@(NSApp.keyWindow.windowNumber),@"own_windows":ownCG()} mutableCopy];
 if(stole){[prev activateWithOptions:0];spin(.8);d[@"restored_front"]=NSWorkspace.sharedWorkspace.frontmostApplication.localizedName?:@"";}
 [rows addObject:d];save();fprintf(stderr,"%s -> front=%s stole=%d\n",step.UTF8String,f.localizedName.UTF8String,stole);
}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<2){fprintf(stderr,"usage: activation-lab OUT.json [holdSeconds]\n");return 2;}outPath=@(argv[1]);rows=[NSMutableArray new];
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; // Regular: it CAN become active
 prev=NSWorkspace.sharedWorkspace.frontmostApplication;
 CGDirectDisplayID ids[16];uint32_t n=0;CGGetActiveDisplayList(16,ids,&n);CGDirectDisplayID hid=0;for(uint32_t i=0;i<n;i++)if(ids[i]!=CGMainDisplayID())hid=ids[i];if(!hid)return 3;
 NSScreen *sc=nil;for(NSScreen *s in NSScreen.screens)if([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==hid)sc=s;if(!sc)return 4;
 NSRect f=sc.frame;NSRect r=NSMakeRect(f.origin.x+700,f.origin.y+f.size.height-500,520,240); // >=700px from the shared edge
 W=[[NSWindow alloc]initWithContentRect:r styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO screen:sc];W.title=@"activation-lab";W.releasedWhenClosed=NO;[W setFrame:r display:NO];
 tf=[[NSTextField alloc]initWithFrame:NSMakeRect(20,150,480,32)];[W.contentView addSubview:tf];[W orderFrontRegardless];spin(.5);
 [rows addObject:@{@"setup":@{@"pid":@(getpid()),@"wid":@(W.windowNumber),@"prev_front":prev.localizedName?:@"",@"prev_pid":@(prev.processIdentifier),@"frame":NSStringFromRect(W.frame)}}];save();
 double t;
 t=now();[W makeKeyAndOrderFront:nil];spin(1.0);record(@"A1 makeKeyAndOrderFront",t);
 t=now();[NSApp activate];spin(1.2);record(@"A2 [NSApp activate] (macOS14 cooperative API)",t);
 t=now();[NSApp activateIgnoringOtherApps:YES];spin(1.2);record(@"A3 activateIgnoringOtherApps:YES",t);
 t=now();[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];spin(1.2);record(@"A4 NSRunningApplication self activateWithOptions:IgnoringOtherApps",t);
 t=now();[NSApp requestUserAttention:NSCriticalRequest];spin(1.0);record(@"A5 requestUserAttention critical (dock bounce)",t);
 t=now();NSAlert *al=[NSAlert new];al.messageText=@"activation-lab detached alert";[al addButtonWithTitle:@"OK"];NSWindow *aw=al.window;(void)aw;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[NSApp abortModal];[al.window orderOut:nil];});
  [al runModal];spin(.3);record(@"A6 NSAlert runModal detached (app-modal)",t);
 t=now();NSOpenPanel *op=[NSOpenPanel openPanel];op.directoryURL=[NSURL fileURLWithPath:NSTemporaryDirectory()];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[op cancel:nil];});
  [op runModal];spin(.3);record(@"A7 NSOpenPanel runModal standalone (app-modal)",t);
 t=now();NSSavePanel *sp=[NSSavePanel savePanel];sp.directoryURL=[NSURL fileURLWithPath:NSTemporaryDirectory()];[sp beginSheetModalForWindow:W completionHandler:^(NSModalResponse r){}];spin(1.5);
  NSMutableDictionary *pan=[@{@"panel_frame":NSStringFromRect(sp.frame),@"panel_isKey":@(sp.isKeyWindow)} mutableCopy];[sp cancel:nil];spin(.4);record(@"A8 NSSavePanel sheet on parked window",t);[rows.lastObject addEntriesFromDictionary:pan];save();
 t=now();NSWindow *w2=[[NSWindow alloc]initWithContentRect:NSMakeRect(f.origin.x+900,f.origin.y+200,400,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO screen:sc];w2.title=@"activation-lab second window";w2.releasedWhenClosed=NO;[w2 makeKeyAndOrderFront:nil];spin(1.0);record(@"A9 new window makeKeyAndOrderFront on hidden display",t);[w2 close];
 t=now();[NSApp unhide:nil];[NSApp arrangeInFront:nil];spin(1.0);record(@"A10 unhide + arrangeInFront",t);
 if(argc>2){double hold=atof(argv[2]);NSDate *end=[NSDate dateWithTimeIntervalSinceNow:hold];NSString *cmdPath=[outPath stringByAppendingString:@".cmd"];
  while([end timeIntervalSinceNow]>0){spin(.1);NSString *cmd=[NSString stringWithContentsOfFile:cmdPath encoding:NSUTF8StringEncoding error:nil];if(!cmd.length)continue;[[NSFileManager defaultManager] removeItemAtPath:cmdPath error:nil];cmd=[cmd stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
   if([cmd hasPrefix:@"record "]){record([cmd substringFromIndex:7],now()-1);}else if([cmd isEqual:@"quit"])break;}}
 save();[W close];return 0;
}}
