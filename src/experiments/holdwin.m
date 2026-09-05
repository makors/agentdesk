#import <AppKit/AppKit.h>
#import <dlfcn.h>
int main(int argc,const char**argv){@autoreleasepool{
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
 CGDirectDisplayID ids[16];uint32_t n=0;CGGetActiveDisplayList(16,ids,&n);CGDirectDisplayID hid=0;for(uint32_t i=0;i<n;i++)if(ids[i]!=CGMainDisplayID())hid=ids[i];
 NSScreen *sc=nil;for(NSScreen *s in NSScreen.screens)if([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==hid)sc=s;if(!sc){fprintf(stderr,"no hidden\n");return 3;}
 NSRect r=NSMakeRect(sc.frame.origin.x+300,sc.frame.origin.y+300,500,300);NSWindow *w=[[NSWindow alloc]initWithContentRect:r styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO screen:sc];w.title=@"holdwin";[w setReleasedWhenClosed:NO];[w setFrame:r display:NO];[w orderFrontRegardless];
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
 // own-connection positive control
 void*SL=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);int(*cid)(void)=dlsym(SL,"SLSMainConnectionID");CGError(*mv)(int,uint32_t,CGPoint*)=dlsym(SL,"SLSMoveWindow");
 CGPoint p=CGPointMake(sc.frame.origin.x+900,sc.frame.origin.y+300);CGError e=mv?mv(cid(),(uint32_t)w.windowNumber,&p):-999;
 printf("{\"pid\":%d,\"wid\":%ld,\"own_move_err\":%d}\n",getpid(),(long)w.windowNumber,e);fflush(stdout);
 [NSApp run];
}return 0;}
