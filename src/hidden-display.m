// hidden-display: create a hidden virtual display and place it so the pointer cannot cross into it.
// Strategy: place the virtual display's top-left at the main display's bottom-right corner, so the two
// displays share exactly one point (a corner), not an edge. macOS lets the pointer move between displays
// only along a shared EDGE, so a corner-only touch means the pointer cannot enter by ordinary movement.
// Reads back the real arrangement and reports the shared-edge length with every other display.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <signal.h>
@interface CGVirtualDisplay:NSObject @property(readonly,nonatomic) unsigned int displayID; -(id)initWithDescriptor:(id)d; -(BOOL)applySettings:(id)s; @end
@interface CGVirtualDisplayDescriptor:NSObject @property(nonatomic) unsigned int vendorID,productID,serialNum; @property(strong,nonatomic) NSString*name; @property(nonatomic) CGSize sizeInMillimeters; @property(nonatomic) unsigned int maxPixelsWide,maxPixelsHigh; @property(nonatomic) CGPoint redPrimary,greenPrimary,bluePrimary,whitePoint; @property(strong,nonatomic) id queue; @property(nonatomic) unsigned int serialNumber; -(void)setDispatchQueue:(id)q; @end
@interface CGVirtualDisplayMode:NSObject -(id)initWithWidth:(unsigned int)w height:(unsigned int)h refreshRate:(double)r; @end
@interface CGVirtualDisplaySettings:NSObject @property(strong,nonatomic) NSArray*modes; @property(nonatomic) unsigned int hiDPI,rotation; @end
static CGVirtualDisplay *vd; static BOOL stop=NO; static NSString *statePath;
// shared-edge length between two rects (0 means only a corner or a gap)
static double sharedEdge(CGRect a,CGRect b){
 double ox=MAX(0,MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(a.origin.x,b.origin.x));
 double oy=MAX(0,MIN(CGRectGetMaxY(a),CGRectGetMaxY(b))-MAX(a.origin.y,b.origin.y));
 BOOL touchV=(fabs(CGRectGetMaxX(a)-b.origin.x)<1||fabs(CGRectGetMaxX(b)-a.origin.x)<1); // vertical shared edge
 BOOL touchH=(fabs(CGRectGetMaxY(a)-b.origin.y)<1||fabs(CGRectGetMaxY(b)-a.origin.y)<1); // horizontal shared edge
 if(touchV)return oy; if(touchH)return ox; return 0;
}
static void report(void){
 CGDirectDisplayID ids[16];uint32_t n=0;CGGetActiveDisplayList(16,ids,&n);CGRect hb=CGDisplayBounds(vd.displayID);
 NSMutableArray *arr=[NSMutableArray new];double maxShare=0;
 for(uint32_t i=0;i<n;i++){CGRect b=CGDisplayBounds(ids[i]);BOOL isHidden=(ids[i]==vd.displayID);
  double sh=isHidden?-1:sharedEdge(hb,b);if(!isHidden)maxShare=MAX(maxShare,sh);
  [arr addObject:@{@"id":@(ids[i]),@"main":@(ids[i]==CGMainDisplayID()),@"hidden":@(isHidden),@"bounds":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)],@"shared_edge_px_with_hidden":@(sh)}];}
 NSDictionary *d=@{@"hidden_display":@(vd.displayID),@"hidden_bounds":@[@(hb.origin.x),@(hb.origin.y),@(hb.size.width),@(hb.size.height)],@"displays":arr,@"max_shared_edge_with_hidden_px":@(maxShare),@"pointer_can_cross_into_hidden":@(maxShare>=1),@"pid":@(getpid())};
 [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil] writeToFile:statePath atomically:YES];
}
int main(int argc,const char**argv){@autoreleasepool{
 if(argc<2){fprintf(stderr,"usage: hidden-display STATE.json [corner|gap|edge]\n");return 2;}statePath=@(argv[1]);
 NSString *mode=argc>2?@(argv[2]):@"corner";
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 CGVirtualDisplayDescriptor *d=[CGVirtualDisplayDescriptor new];[d setDispatchQueue:dispatch_get_main_queue()];d.name=@"agentdesk hidden workspace";d.maxPixelsWide=1920;d.maxPixelsHigh=1200;d.sizeInMillimeters=CGSizeMake(510,320);d.vendorID=0x3456;d.productID=0x9240;d.serialNum=0x5150;d.serialNumber=0x5150;d.whitePoint=CGPointMake(.3125,.3291);d.redPrimary=CGPointMake(.6797,.3203);d.greenPrimary=CGPointMake(.2559,.6983);d.bluePrimary=CGPointMake(.1494,.0557);
 vd=[[CGVirtualDisplay alloc]initWithDescriptor:d];if(!vd)return 3;CGVirtualDisplaySettings *s=[CGVirtualDisplaySettings new];s.hiDPI=0;s.modes=@[[[CGVirtualDisplayMode alloc]initWithWidth:1920 height:1200 refreshRate:60]];if(![vd applySettings:s])return 4;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  CGRect main=CGDisplayBounds(CGMainDisplayID());int32_t x,y;
  if([mode isEqual:@"corner"]){x=(int32_t)CGRectGetMaxX(main);y=(int32_t)CGRectGetMaxY(main);}       // touch bottom-right corner only
  else if([mode isEqual:@"gap"]){x=(int32_t)CGRectGetMaxX(main)+400;y=(int32_t)CGRectGetMaxY(main)+400;} // fully detached
  else {x=(int32_t)CGRectGetMaxX(main);y=0;}                                                            // classic right-edge (crossable)
  CGDisplayConfigRef c=NULL;CGError e=CGBeginDisplayConfiguration(&c);
  if(e==0)e=CGConfigureDisplayMirrorOfDisplay(c,vd.displayID,kCGNullDirectDisplay);
  if(e==0)e=CGConfigureDisplayOrigin(c,vd.displayID,x,y);
  if(e==0)e=CGCompleteDisplayConfiguration(c,kCGConfigureForSession);else if(c)CGCancelDisplayConfiguration(c);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{report();});
 });
 signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
 void(^teardown)(void)=^{vd=nil;[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];[[NSJSONSerialization dataWithJSONObject:@{@"stopped":@1} options:0 error:nil] writeToFile:statePath atomically:YES];exit(0);};
 dispatch_source_t st=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());dispatch_source_set_event_handler(st,teardown);dispatch_resume(st);
 dispatch_source_t si=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());dispatch_source_set_event_handler(si,teardown);dispatch_resume(si);
 [NSApp run];
}return 0;}
