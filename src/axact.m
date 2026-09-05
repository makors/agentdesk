// axact: exact-window Accessibility actor for any process (generalisation of Codex's fixture-only tool).
// Safety invariants: the CGWindowID must be owned by the PID (WindowServer check), the AX window must map
// to that exact CGWindowID via _AXUIElementGetWindow, and every acted-upon element must re-verify that
// its containing AX window is the requested one. No keyboard or pointer events are ever posted.
// Usage:
//   axact windows [PID]                              list layer-0 windows (pid, wid, app, title, bounds)
//   axact tree PID WID [maxdepth]                    dump exact-window AX tree (role, id, title, value)
//   axact find PID WID ROLE|* [TITLE-or-ID substring] list matching elements (index, role, title, id, value)
//   axact set PID WID SELECTOR VALUE                 set AXValue on element
//   axact insert PID WID SELECTOR TEXT               insert text at caret (AXSelectedText)
//   axact press PID WID SELECTOR                     AXPress
//   axact raise PID WID                              AXRaise the window (NOT isolation; diagnostic only)
//   axact focused PID                                report app's AXFocusedWindow / AXFocusedUIElement
//   axact move PID WID X Y                           set AXPosition of window
//   axact menu PID "Menu>Item>Subitem"               press a menu-bar item by path (background app)
//   SELECTOR := id=<AXIdentifier> | title=<AXTitle> | role=<AXRole>[#n] | path=<i>/<j>/<k> (child indices)
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
typedef AXError(*WinFn)(AXUIElementRef,CGWindowID*); static WinFn axWin;
static id get(AXUIElementRef e,CFStringRef k){CFTypeRef v=NULL;if(AXUIElementCopyAttributeValue(e,k,&v)!=kAXErrorSuccess||!v)return nil;return CFBridgingRelease(v);}
static NSString *str(id v){return [v isKindOfClass:NSString.class]?v:([v isKindOfClass:NSNumber.class]?[v stringValue]:(v?[NSString stringWithFormat:@"<%@>",[v class]]:@""));}
static BOOL ownerMatches(pid_t pid,CGWindowID wid){NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in all)if([w[(id)kCGWindowNumber] unsignedIntValue]==wid&&[w[(id)kCGWindowOwnerPID] intValue]==pid)return YES;return NO;}
static AXUIElementRef exactWindow(pid_t pid,CGWindowID wid,int *code){
 if(!ownerMatches(pid,wid)){*code=4;return NULL;}
 AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,2.0);id ws=get(app,kAXWindowsAttribute);AXUIElementRef hit=NULL;int matches=0;
 for(id w in ([ws isKindOfClass:NSArray.class]?ws:@[])){CGWindowID n=0;if(axWin((__bridge AXUIElementRef)w,&n)==0&&n==wid){hit=(__bridge AXUIElementRef)w;matches++;}}
 if(matches!=1){CFRelease(app);*code=6;return NULL;}
 CFRetain(hit);CFRelease(app);return hit;
}
static BOOL memberOf(AXUIElementRef el,pid_t pid,CGWindowID wid){pid_t o=0;AXUIElementGetPid(el,&o);if(o!=pid)return NO;id w=get(el,kAXWindowAttribute);CGWindowID c=0;if(!w||axWin((__bridge AXUIElementRef)w,&c)!=0)return NO;return c==wid;}
static void walk(AXUIElementRef e,int depth,int maxd,void(^fn)(AXUIElementRef,int,NSString*),NSString *path,int *budget){
 if(depth>maxd||--*budget<0)return;fn(e,depth,path);id ch=get(e,kAXChildrenAttribute);if(![ch isKindOfClass:NSArray.class])return;int i=0;
 for(id c in ch){walk((__bridge AXUIElementRef)c,depth+1,maxd,fn,[path stringByAppendingFormat:@"%@%d",path.length?@"/":@"",i],budget);i++;}
}
static AXUIElementRef selectEl(AXUIElementRef win,NSString *sel,int *code){
 __block AXUIElementRef found=NULL;__block int nth=0;int budget=5000;
 if([sel hasPrefix:@"path="]){NSArray *parts=[[sel substringFromIndex:5] componentsSeparatedByString:@"/"];AXUIElementRef cur=(AXUIElementRef)CFRetain(win);for(NSString *p in parts){id ch=get(cur,kAXChildrenAttribute);NSInteger i=p.integerValue;if(![ch isKindOfClass:NSArray.class]||i<0||i>=[ch count]){CFRelease(cur);*code=7;return NULL;}AXUIElementRef nx=(AXUIElementRef)CFRetain((__bridge CFTypeRef)ch[i]);CFRelease(cur);cur=nx;}return cur;}
 NSString *key=nil,*val=nil;NSInteger want=0;
 if([sel hasPrefix:@"id="]){key=@"AXIdentifier";val=[sel substringFromIndex:3];}else if([sel hasPrefix:@"title="]){key=@"AXTitle";val=[sel substringFromIndex:6];}else if([sel hasPrefix:@"role="]){key=@"AXRole";val=[sel substringFromIndex:5];NSRange h=[val rangeOfString:@"#"];if(h.location!=NSNotFound){want=[val substringFromIndex:h.location+1].integerValue;val=[val substringToIndex:h.location];}}else{*code=2;return NULL;}
 walk(win,0,40,^(AXUIElementRef e,int d,NSString *p){if(found)return;id v=get(e,(__bridge CFStringRef)key);if([str(v) isEqual:val]){if(nth==want){found=(AXUIElementRef)CFRetain(e);}nth++;}},@"",&budget);
 if(!found)*code=7;return found;
}
static int fail(int code,const char *msg){printf("{\"ok\":false,\"code\":%d,\"error\":\"%s\"}\n",code,msg);return code;}
int main(int argc,const char **argv){@autoreleasepool{
 axWin=(WinFn)dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");if(!axWin)return fail(5,"no _AXUIElementGetWindow");
 if(!AXIsProcessTrusted())return fail(1,"Accessibility not granted to this process");
 if(argc<2)return fail(2,"usage");NSString *cmd=@(argv[1]);
 if([cmd isEqual:@"windows"]){pid_t filter=argc>2?atoi(argv[2]):0;NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll|kCGWindowListExcludeDesktopElements,kCGNullWindowID));NSMutableArray *out=[NSMutableArray new];
  for(NSDictionary *w in all){if([w[(id)kCGWindowLayer] intValue]!=0)continue;pid_t pid=[w[(id)kCGWindowOwnerPID] intValue];if(filter&&pid!=filter)continue;CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);if(b.size.width<50||b.size.height<40)continue;
   [out addObject:@{@"pid":@(pid),@"wid":w[(id)kCGWindowNumber],@"app":w[(id)kCGWindowOwnerName]?:@"",@"title":w[(id)kCGWindowName]?:@"",@"onscreen":w[(id)kCGWindowIsOnscreen]?:@NO,@"bounds":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)]}];}
  printf("%s\n",[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil] encoding:NSUTF8StringEncoding].UTF8String);return 0;}
 if([cmd isEqual:@"focused"]){if(argc<3)return fail(2,"usage");pid_t pid=atoi(argv[2]);AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,1.0);id fw=get(app,kAXFocusedWindowAttribute);id fe=get(app,kAXFocusedUIElementAttribute);CGWindowID fwid=0,fewid=0;if(fw)axWin((__bridge AXUIElementRef)fw,&fwid);id few=fe?get((__bridge AXUIElementRef)fe,kAXWindowAttribute):nil;if(few)axWin((__bridge AXUIElementRef)few,&fewid);
  printf("{\"ok\":true,\"pid\":%d,\"focused_window\":%u,\"focused_window_title\":\"%s\",\"focused_element_role\":\"%s\",\"focused_element_window\":%u,\"frontmost\":%s}\n",pid,fwid,str(fw?get((__bridge AXUIElementRef)fw,kAXTitleAttribute):nil).UTF8String,str(fe?get((__bridge AXUIElementRef)fe,kAXRoleAttribute):nil).UTF8String,fewid,[get(app,kAXFrontmostAttribute) boolValue]?"true":"false");CFRelease(app);return 0;}
 if([cmd isEqual:@"menu"]){if(argc<4)return fail(2,"usage");pid_t pid=atoi(argv[2]);NSArray *path=[@(argv[3]) componentsSeparatedByString:@">"];AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,2.0);id bar=get(app,kAXMenuBarAttribute);if(!bar)return fail(7,"no menu bar");AXUIElementRef cur=(AXUIElementRef)CFRetain((__bridge CFTypeRef)bar);
  for(NSString *seg in path){id ch=get(cur,kAXChildrenAttribute);AXUIElementRef nx=NULL;for(id c in ([ch isKindOfClass:NSArray.class]?ch:@[])){id t=get((__bridge AXUIElementRef)c,kAXTitleAttribute);if([str(t) isEqual:seg]){nx=(__bridge AXUIElementRef)c;break;}
    // menu items contain an AXMenu child holding the sub-items
    id sub=get((__bridge AXUIElementRef)c,kAXChildrenAttribute);if([sub isKindOfClass:NSArray.class]&&[sub count]==1){id gc=get((__bridge AXUIElementRef)sub[0],kAXChildrenAttribute);(void)gc;}}
   if(!nx){CFRelease(cur);return fail(7,[[NSString stringWithFormat:@"menu segment not found: %@",seg] UTF8String]);}
   CFRetain(nx);CFRelease(cur);cur=nx;id ch2=get(cur,kAXChildrenAttribute);if([ch2 isKindOfClass:NSArray.class]&&[ch2 count]==1&&[str(get((__bridge AXUIElementRef)ch2[0],kAXRoleAttribute)) isEqual:@"AXMenu"]&&seg!=path.lastObject){AXUIElementRef m=(AXUIElementRef)CFRetain((__bridge CFTypeRef)ch2[0]);CFRelease(cur);cur=m;}}
  AXError e=AXUIElementPerformAction(cur,kAXPressAction);printf("{\"ok\":%s,\"ax_error\":%d}\n",e==0?"true":"false",e);CFRelease(cur);CFRelease(app);return e?9:0;}

 if([cmd isEqual:@"watchmove"]){ // watchmove PID X Y TIMEOUT_MS [MINW MINH] : move the next NEW layer-0 window of PID to (X,dst) ASAP
  if(argc<6)return fail(2,"usage");pid_t pid=atoi(argv[2]);double X=atof(argv[3]);double Y=atof(argv[4]);int tmo=atoi(argv[5]);int minw=argc>6?atoi(argv[6]):200,minh=argc>7?atoi(argv[7]):120;
  NSMutableSet *base=[NSMutableSet new];NSArray *all=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));for(NSDictionary *w in all)if([w[(id)kCGWindowOwnerPID] intValue]==pid&&[w[(id)kCGWindowLayer] intValue]==0)[base addObject:w[(id)kCGWindowNumber]];
  double t0=[NSDate date].timeIntervalSince1970;CGWindowID hit=0;CGRect hb={{0,0},{0,0}};double tAppear=0;
  while([NSDate date].timeIntervalSince1970-t0<tmo/1000.0){
   NSArray *cur=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));
   for(NSDictionary *w in cur){if([w[(id)kCGWindowOwnerPID] intValue]!=pid||[w[(id)kCGWindowLayer] intValue]!=0)continue;NSNumber *wid=w[(id)kCGWindowNumber];if([base containsObject:wid])continue;CGRect b;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&b);if(b.size.width<minw||b.size.height<minh)continue;hit=[wid unsignedIntValue];hb=b;tAppear=[NSDate date].timeIntervalSince1970;break;}
   if(hit)break;usleep(2000);
  }
  if(!hit){printf("{\"ok\":false,\"error\":\"no new window within timeout\"}\n");return 1;}
  int code=0;AXUIElementRef win=exactWindow(pid,hit,&code);double tResolved=[NSDate date].timeIntervalSince1970;
  if(!win){printf("{\"ok\":false,\"appeared_bounds\":[%.0f,%.0f,%.0f,%.0f],\"error\":\"cannot resolve AX window\",\"code\":%d}\n",hb.origin.x,hb.origin.y,hb.size.width,hb.size.height,code);return 1;}
  CGPoint p=CGPointMake(X,Y);AXValueRef v=AXValueCreate(kAXValueCGPointType,&p);AXError e=AXUIElementSetAttributeValue(win,kAXPositionAttribute,v);CFRelease(v);double tMoved=[NSDate date].timeIntervalSince1970;
  id np=get(win,kAXPositionAttribute);CGPoint a={0,0};if(np)AXValueGetValue((__bridge AXValueRef)np,kAXValueCGPointType,&a);CFRelease(win);
  printf("{\"ok\":%s,\"wid\":%u,\"appeared_bounds\":[%.0f,%.0f,%.0f,%.0f],\"appeared_on_main\":%s,\"final_pos\":[%.0f,%.0f],\"ax_error\":%d,\"ms_detect\":%.1f,\"ms_resolve\":%.1f,\"ms_move\":%.1f,\"ms_total_onscreen_main\":%.1f}\n",e==0?"true":"false",hit,hb.origin.x,hb.origin.y,hb.size.width,hb.size.height,hb.origin.x<1512?"true":"false",a.x,a.y,e,(tAppear-t0)*1000,(tResolved-tAppear)*1000,(tMoved-tResolved)*1000,(tMoved-tAppear)*1000);
  return e?9:0;
 }
 if(argc<4)return fail(2,"usage");pid_t pid=atoi(argv[2]);CGWindowID wid=(CGWindowID)strtoul(argv[3],NULL,10);int code=0;AXUIElementRef win=exactWindow(pid,wid,&code);if(!win)return fail(code,code==4?"window not owned by pid":"AX window unresolved or ambiguous");
 if([cmd isEqual:@"tree"]){int maxd=argc>4?atoi(argv[4]):6;int budget=3000;walk(win,0,maxd,^(AXUIElementRef e,int d,NSString *p){printf("%*s[%s] %s id=%s title=%s value=%s\n",d*2,"",p.UTF8String,str(get(e,kAXRoleAttribute)).UTF8String,str(get(e,CFSTR("AXIdentifier"))).UTF8String,str(get(e,kAXTitleAttribute)).UTF8String,[str(get(e,kAXValueAttribute)) substringToIndex:MIN(60,str(get(e,kAXValueAttribute)).length)].UTF8String);},@"",&budget);return 0;}
 if([cmd isEqual:@"find"]){NSString *role=argc>4?@(argv[4]):@"*",*needle=argc>5?@(argv[5]):nil;int budget=5000;walk(win,0,40,^(AXUIElementRef e,int d,NSString *p){NSString *r=str(get(e,kAXRoleAttribute)),*t=str(get(e,kAXTitleAttribute)),*i=str(get(e,CFSTR("AXIdentifier"))),*v=str(get(e,kAXValueAttribute));if(![role isEqual:@"*"]&&![r isEqual:role])return;if(needle&&![t containsString:needle]&&![i containsString:needle]&&![v containsString:needle])return;printf("path=%s role=%s title=%s id=%s value=%s\n",p.UTF8String,r.UTF8String,t.UTF8String,i.UTF8String,[v substringToIndex:MIN(80,v.length)].UTF8String);},@"",&budget);return 0;}
 if([cmd isEqual:@"raise"]){AXError e=AXUIElementPerformAction(win,kAXRaiseAction);printf("{\"ok\":%s,\"ax_error\":%d,\"note\":\"raise is not isolation\"}\n",e==0?"true":"false",e);return e?9:0;}
 if([cmd isEqual:@"move"]){if(argc<6)return fail(2,"usage");CGPoint p=CGPointMake(atof(argv[4]),atof(argv[5]));AXValueRef v=AXValueCreate(kAXValueCGPointType,&p);AXError e=AXUIElementSetAttributeValue(win,kAXPositionAttribute,v);CFRelease(v);id np=get(win,kAXPositionAttribute);CGPoint a={0,0};if(np)AXValueGetValue((__bridge AXValueRef)np,kAXValueCGPointType,&a);printf("{\"ok\":%s,\"ax_error\":%d,\"position\":[%.0f,%.0f]}\n",e==0?"true":"false",e,a.x,a.y);return e?9:0;}
 if(argc<5)return fail(2,"usage");NSString *sel=@(argv[4]);AXUIElementRef el=selectEl(win,sel,&code);if(!el)return fail(code,"element not found in exact window");
 if(!memberOf(el,pid,wid)){CFRelease(el);return fail(8,"element membership mismatch");}
 AXError e=kAXErrorIllegalArgument;NSString *readback=@"";
 if([cmd isEqual:@"set"]&&argc>=6){Boolean s=false;AXUIElementIsAttributeSettable(el,kAXValueAttribute,&s);if(!s){CFRelease(el);return fail(10,"AXValue not settable");}e=AXUIElementSetAttributeValue(el,kAXValueAttribute,(__bridge CFStringRef)@(argv[5]));readback=str(get(el,kAXValueAttribute));}
 else if([cmd isEqual:@"insert"]&&argc>=6){Boolean s=false;AXUIElementIsAttributeSettable(el,kAXSelectedTextAttribute,&s);if(!s){CFRelease(el);return fail(10,"AXSelectedText not settable");}e=AXUIElementSetAttributeValue(el,kAXSelectedTextAttribute,(__bridge CFStringRef)@(argv[5]));readback=str(get(el,kAXValueAttribute));}
 else if([cmd isEqual:@"press"]){CFArrayRef acts=NULL;AXUIElementCopyActionNames(el,&acts);BOOL ok=acts&&[(__bridge NSArray*)acts containsObject:(__bridge NSString*)kAXPressAction];if(acts)CFRelease(acts);if(!ok){CFRelease(el);return fail(10,"no AXPress action");}e=AXUIElementPerformAction(el,kAXPressAction);}
 else if([cmd isEqual:@"get"]){e=0;readback=str(get(el,kAXValueAttribute));}
 else {CFRelease(el);return fail(2,"unknown command");}
 // Re-verify membership after the action: the element must still belong to the exact window.
 BOOL still=memberOf(el,pid,wid);
 NSDictionary *r=@{@"ok":@(e==0),@"ax_error":@(e),@"pid":@(pid),@"wid":@(wid),@"selector":sel,@"readback":readback,@"membership_after":@(still)};
 printf("%s\n",[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:r options:0 error:nil] encoding:NSUTF8StringEncoding].UTF8String);CFRelease(el);CFRelease(win);return e?9:0;
}}
