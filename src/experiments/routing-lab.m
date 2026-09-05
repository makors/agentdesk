// routing-lab: disposable two-window AppKit fixture placed on the hidden display.
// It never activates itself. It measures AppKit key-event routing rules inside one process:
//  - does -[NSApplication sendEvent:] honour NSEvent.window for key events?
//  - does a sheet (NSOpenPanel) on the agent window take key from the human window?
//  - can key be reassigned while the sheet is open, and does routing follow?
//  - owner-side probes: SLSSetWindowActive on the human window.
// Human stand-in keys are injected via -[NSApplication postEvent:atStart:] (in-process) and,
// where possible, via CGEventPostToPid to self (CG path). Results are written as JSON.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
static NSWindow *H,*A; static NSTextField *hf,*af; static NSOpenPanel *panel; static NSMutableArray *logRows; static NSString *outPath; static NSMutableArray *keyNotes;
static NSString *S(NSString *s){return s?:@"";}
static NSArray *ownCG(void){NSMutableArray *o=[NSMutableArray new];NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in all){if([w[(id)kCGWindowOwnerPID] intValue]!=getpid())continue;CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);[o addObject:[NSString stringWithFormat:@"wid=%@ layer=%@ cg=(%.0f,%.0f %.0fx%.0f) on=%@",w[(id)kCGWindowNumber],w[(id)kCGWindowLayer],b.origin.x,b.origin.y,b.size.width,b.size.height,w[(id)kCGWindowIsOnscreen]]];}return o;}

static NSDictionary *state(NSString *label){
 NSDictionary *d=@{@"step":label,@"keyWindow":@(NSApp.keyWindow.windowNumber),@"H_isKey":@(H.isKeyWindow),@"A_isKey":@(A.isKeyWindow),@"panel_isKey":@(panel?panel.isKeyWindow:NO),@"panel_visible":@(panel.visible),@"panel_wid":@(panel.windowNumber),@"H":S(hf.stringValue),@"A":S(af.stringValue),@"panel_frame":panel?NSStringFromRect(panel.frame):@"",@"front_pid":@(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier),@"app_active":@(NSApp.isActive),@"key_notes":[keyNotes copy],@"own_cg_windows":ownCG(),@"panel_wid":@(panel.windowNumber),@"H_first":NSStringFromClass([H.firstResponder class])?:@"",@"A_first":NSStringFromClass([A.firstResponder class])?:@""};
 [keyNotes removeAllObjects];[logRows addObject:d];return d;
}
static void save(void){[[NSJSONSerialization dataWithJSONObject:logRows options:NSJSONWritingPrettyPrinted error:nil] writeToFile:outPath atomically:YES];}
static void postKey(unichar c,NSInteger winNum){
 NSString *s=[NSString stringWithCharacters:&c length:1];
 NSEvent *d=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:winNum context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
 NSEvent *u=[NSEvent keyEventWithType:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:winNum context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
 [NSApp postEvent:d atStart:NO];[NSApp postEvent:u atStart:NO];
}
static void cgKey(unichar c){CGEventRef d=CGEventCreateKeyboardEvent(NULL,0,true);CGEventKeyboardSetUnicodeString(d,1,&c);CGEventRef u=CGEventCreateKeyboardEvent(NULL,0,false);CGEventKeyboardSetUnicodeString(u,1,&c);CGEventPostToPid(getpid(),d);CGEventPostToPid(getpid(),u);CFRelease(d);CFRelease(u);}
static void spin(double s){NSDate *dl=[NSDate dateWithTimeIntervalSinceNow:s];while([dl timeIntervalSinceNow]>0){NSEvent *e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:dl inMode:NSDefaultRunLoopMode dequeue:YES];if(e)[NSApp sendEvent:e];[NSApp updateWindows];}}

static NSWindow *mk(NSString *title,NSRect r,NSScreen *sc,NSTextField * __strong *f){NSWindow *w=[[NSWindow alloc]initWithContentRect:r styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO screen:sc];w.title=title;w.releasedWhenClosed=NO;[w setFrame:r display:NO];*f=[[NSTextField alloc]initWithFrame:NSMakeRect(20,120,460,32)];(*f).stringValue=@"";[w.contentView addSubview:*f];[w orderFrontRegardless];return w;}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<2){fprintf(stderr,"usage: routing-lab OUT.json\n");return 2;}outPath=@(argv[1]);logRows=[NSMutableArray new];keyNotes=[NSMutableArray new];
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
 CGDirectDisplayID ids[16];uint32_t n=0;CGGetActiveDisplayList(16,ids,&n);CGDirectDisplayID hid=0;for(uint32_t i=0;i<n;i++)if(ids[i]!=CGMainDisplayID())hid=ids[i];
 if(!hid){fprintf(stderr,"no hidden display\n");return 3;}
 NSScreen *sc=nil;for(NSScreen *s in NSScreen.screens)if([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==hid)sc=s;if(!sc)return 4;
 NSRect f=sc.frame;A=mk(@"routing-lab agent",NSMakeRect(f.origin.x+40,f.origin.y+f.size.height-420,500,200),sc,&af);H=mk(@"routing-lab human",NSMakeRect(f.origin.x+600,f.origin.y+f.size.height-420,500,200),sc,&hf);
 [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *no){[keyNotes addObject:[NSString stringWithFormat:@"becameKey:%ld",(long)[no.object windowNumber]]];}];
 [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:nil queue:nil usingBlock:^(NSNotification *no){[keyNotes addObject:[NSString stringWithFormat:@"resignedKey:%ld",(long)[no.object windowNumber]]];}];
 [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e){[keyNotes addObject:[NSString stringWithFormat:@"keyDown(%@)->win %ld",e.characters,(long)e.windowNumber]];return e;}];
 spin(.5);
 [A makeFirstResponder:af];[H makeKeyWindow];[H makeFirstResponder:hf];spin(.3);
 NSMutableDictionary *first=[state(@"0 setup: H makeKeyWindow, first responders set") mutableCopy];first[@"windows"]=@{@"A":@(A.windowNumber),@"H":@(H.windowNumber),@"hidden_display":@(hid),@"A_frame":NSStringFromRect(A.frame),@"H_frame":NSStringFromRect(H.frame)};[logRows replaceObjectAtIndex:logRows.count-1 withObject:first];
 // 1. postEvent with explicit window numbers
 postKey('q',A.windowNumber);spin(.3);state(@"1a postEvent 'q' window=A");
 postKey('r',H.windowNumber);spin(.3);state(@"1b postEvent 'r' window=H");
 postKey('s',0);spin(.3);state(@"1c postEvent 's' window=0");
 // 2. CGEventPostToPid to self
 cgKey('t');spin(.4);state(@"2 CGEventPostToPid(self) 't'");
 // 3. sheet on agent window
 panel=[NSOpenPanel openPanel];panel.directoryURL=[NSURL fileURLWithPath:NSTemporaryDirectory()];[panel beginSheetModalForWindow:A completionHandler:^(NSModalResponse r){}];spin(1.0);state(@"3 beginSheetModalForWindow:A opened");
 postKey('u',H.windowNumber);spin(.3);state(@"3a postEvent 'u' window=H while sheet open");
 postKey('v',0);spin(.3);state(@"3b postEvent 'v' window=0 while sheet open");
 cgKey('w');spin(.4);state(@"3c CGEventPostToPid(self) 'w' while sheet open");
 // 4. reassign key to H while sheet open
 [H makeKeyWindow];spin(.3);state(@"4 H makeKeyWindow while sheet open");
 postKey('x',0);spin(.3);state(@"4a postEvent 'x' window=0 after re-key H");
 cgKey('y');spin(.4);state(@"4b CGEventPostToPid(self) 'y' after re-key H");
 // 5. owner-side SLSSetWindowActive probe on H (signature guessed: cid, wid, bool)
 [panel makeKeyWindow];spin(.2);state(@"5 panel makeKeyWindow again");
 postKey('z',0);spin(.3);state(@"5a postEvent 'z' window=0 after panel re-key");
 // 6. close sheet
 [panel cancel:nil];spin(.5);state(@"6 panel cancelled");
 postKey('!',0);spin(.3);state(@"6a postEvent '!' window=0 after cancel");
 save();
 if(argc>2){double hold=atof(argv[2]);NSString *statePath=[outPath stringByAppendingString:@".state.json"],*cmdPath=[outPath stringByAppendingString:@".cmd"];NSDate *end=[NSDate dateWithTimeIntervalSinceNow:hold];
  while([end timeIntervalSinceNow]>0){spin(.1);NSDictionary *st=state(@"hold");[logRows removeLastObject];[[NSJSONSerialization dataWithJSONObject:st options:0 error:nil] writeToFile:statePath atomically:YES];
   NSString *cmd=[NSString stringWithContentsOfFile:cmdPath encoding:NSUTF8StringEncoding error:nil];if(!cmd.length)continue;[[NSFileManager defaultManager] removeItemAtPath:cmdPath error:nil];cmd=[cmd stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
   if([cmd isEqual:@"sheet"]){panel=[NSOpenPanel openPanel];panel.directoryURL=[NSURL fileURLWithPath:NSTemporaryDirectory()];[panel beginSheetModalForWindow:A completionHandler:^(NSModalResponse r){}];}
   else if([cmd isEqual:@"cancel"]){[panel cancel:nil];}
   else if([cmd isEqual:@"keyH"]){[H makeKeyWindow];[H makeFirstResponder:hf];}
   else if([cmd isEqual:@"keyA"]){[A makeKeyWindow];[A makeFirstResponder:af];}
   else if([cmd isEqual:@"clear"]){hf.stringValue=@"";af.stringValue=@"";}
   else if([cmd hasPrefix:@"post "]){unichar c=[cmd characterAtIndex:5];postKey(c,0);}
   else if([cmd isEqual:@"quit"])break;}}
 [A close];[H close];spin(.2);
 printf("%s\n",[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:logRows options:NSJSONWritingPrettyPrinted error:nil] encoding:NSUTF8StringEncoding].UTF8String);
}return 0;}
