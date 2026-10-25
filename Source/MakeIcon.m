#import <Cocoa/Cocoa.h>
int main(int argc,const char *argv[]) { @autoreleasepool {
    if(argc!=2)return 1;NSString *dir=@(argv[1]);[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *sizes=@[@16,@32,@128,@256,@512];
    for(NSNumber *n in sizes)for(int scale=1;scale<=2;scale++) {
        int size=n.intValue*scale;
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        NSAffineTransform *t=[NSAffineTransform transform];[t scaleBy:size/1024.0];[t concat];
        NSRect canvas=NSMakeRect(70,70,884,884);NSBezierPath *box=[NSBezierPath bezierPathWithRoundedRect:canvas xRadius:205 yRadius:205];
        NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.18 green:0.22 blue:0.45 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.07 green:0.11 blue:0.22 alpha:1]];[gradient drawInBezierPath:box angle:85];
        [[NSColor colorWithSRGBRed:0.76 green:0.98 blue:0.62 alpha:1] set];
        NSBezierPath *body=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(218,310,588,371) xRadius:73 yRadius:73];body.lineWidth=34;[body stroke];
        NSBezierPath *top=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(350,660,239,75) xRadius:22 yRadius:22];[top fill];
        NSBezierPath *lens=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(395,379,235,235)];lens.lineWidth=31;[lens stroke];
        [[NSColor colorWithWhite:1 alpha:0.85] set];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(701,594,34,34)] fill];
        [NSGraphicsContext restoreGraphicsState];NSString *name=[NSString stringWithFormat:@"icon_%dx%d%@.png",n.intValue,n.intValue,scale==2?@"@2x":@""];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
    }
    return 0;
}}
