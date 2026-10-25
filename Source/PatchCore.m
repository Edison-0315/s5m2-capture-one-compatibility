#import "PatchCore.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach-o/nlist.h>
#import <libkern/OSByteOrder.h>
#import <sys/sysctl.h>

NSString *S5ErrorDomain = @"org.s5m2.compatibility";
static NSString *const KnownHash = @"4a99ec884829011d2297e14eb666d2fb4d90cd54bf88e99e47794967a7a27860";
static NSString *const InitSymbol = @"__GLOBAL__sub_I_PTPPanasonicFactory.cpp";
static NSString *const SupportSymbol = @"__ZN10CaptureOne3PTP9Panasonic16PanasonicFactory11IsSupportedERKNS0_8Protocol10DeviceInfoE";

static void Fail(NSString *message) { @throw [NSException exceptionWithName:@"S5Failure" reason:message userInfo:nil]; }
static void Require(BOOL value, NSString *message) { if (!value) Fail(message); }
static NSError *Error(NSException *ex) { return [NSError errorWithDomain:S5ErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:ex.reason ?: @"Unknown error"}]; }
static BOOL RangeOK(NSUInteger off, NSUInteger len, NSUInteger total) { return off <= total && len <= total-off; }
static uint32_t U32(NSData *d, NSUInteger off) { Require(RangeOK(off,4,d.length),@"文件截断 / Truncated file"); uint32_t x; [d getBytes:&x range:NSMakeRange(off,4)]; return OSSwapLittleToHostInt32(x); }
static uint64_t U64(NSData *d, NSUInteger off) { Require(RangeOK(off,8,d.length),@"文件截断 / Truncated file"); uint64_t x; [d getBytes:&x range:NSMakeRange(off,8)]; return OSSwapLittleToHostInt64(x); }
static uint32_t BE32(NSData *d, NSUInteger off) { return OSSwapInt32(U32(d,off)); }
static uint64_t BE64(NSData *d, NSUInteger off) { return OSSwapInt64(U64(d,off)); }
static NSString *SHA(NSData *d) { unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes,(CC_LONG)d.length,hash); NSMutableString *s=[NSMutableString new]; for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",hash[i]]; return s; }
static NSString *FixedString(NSData *d, NSUInteger offset, NSUInteger length) { Require(RangeOK(offset,length,d.length),@"损坏的名称 / Invalid name"); const char *p=(const char *)d.bytes+offset; NSUInteger n=strnlen(p,length); return [[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] ?: @""; }

static NSArray<NSDictionary *> *Slices(NSData *d) {
    Require(d.length>=32,@"文件太小 / File too small");
    NSMutableArray *result=[NSMutableArray new]; uint32_t magic=U32(d,0);
    if (magic==MH_MAGIC_64) return @[@{@"cpu":@(U32(d,4)),@"subtype":@(U32(d,8)),@"offset":@0,@"size":@(d.length)}];
    BOOL wide=BE32(d,0)==FAT_MAGIC_64;
    Require(wide || BE32(d,0)==FAT_MAGIC,@"不是支持的 Mach-O 文件 / Unsupported Mach-O");
    NSUInteger n=BE32(d,4), stride=wide?32:20;
    Require(n>0 && n<=16 && RangeOK(8,n*stride,d.length),@"无效架构表 / Invalid architecture table");
    for (NSUInteger i=0;i<n;i++) {
        NSUInteger p=8+i*stride; uint64_t off=wide?BE64(d,p+8):BE32(d,p+8), size=wide?BE64(d,p+16):BE32(d,p+12);
        Require(off>=8+n*stride && size>=32 && RangeOK((NSUInteger)off,(NSUInteger)size,d.length),@"无效架构范围 / Invalid slice range");
        for (NSDictionary *other in result) { NSUInteger a=[other[@"offset"] unsignedIntegerValue],b=[other[@"size"] unsignedIntegerValue]; Require(off+size<=a || a+b<=off,@"架构范围重叠 / Overlapping slices"); }
        [result addObject:@{@"cpu":@(BE32(d,p)),@"subtype":@(BE32(d,p+4)),@"offset":@(off),@"size":@(size)}];
    }
    return result;
}

static NSDictionary *Layout(NSData *d) {
    Require(U32(d,0)==MH_MAGIC_64,@"仅支持小端 64 位 Mach-O / Requires little-endian Mach-O64");
    NSUInteger n=U32(d,16),bytes=U32(d,20); Require(n<=2048 && RangeOK(32,bytes,d.length),@"损坏的加载命令 / Invalid load commands");
    NSMutableArray *segments=[NSMutableArray new],*sections=[NSMutableArray new]; NSDictionary *sym=@{}; NSUInteger off=32;
    for(NSUInteger i=0;i<n;i++) {
        Require(RangeOK(off,8,32+bytes),@"损坏的加载命令边界 / Load command bounds"); NSUInteger cmd=U32(d,off),len=U32(d,off+4);
        Require(len>=8 && !(len%4) && RangeOK(off,len,32+bytes),@"损坏的加载命令长度 / Load command size");
        if(cmd==LC_SEGMENT_64) {
            Require(len>=72,@"损坏的段 / Invalid segment"); uint64_t addr=U64(d,off+24), vmSize=U64(d,off+32), fo=U64(d,off+40),fs=U64(d,off+48); NSUInteger ns=U32(d,off+64);
            Require(ns<=4096 && 72+ns*80<=len && RangeOK(fo,fs,d.length),@"损坏的段范围 / Segment bounds");
            [segments addObject:@{@"name":FixedString(d,off+8,16),@"addr":@(addr),@"vmSize":@(vmSize),@"offset":@(fo),@"size":@(fs)}];
            for(NSUInteger j=0;j<ns;j++) { NSUInteger q=off+72+j*80; uint32_t flags=U32(d,q+64); uint64_t sz=U64(d,q+40); NSUInteger f=U32(d,q+48); BOOL zero=(flags&0xff)==S_ZEROFILL || (flags&0xff)==S_GB_ZEROFILL || (flags&0xff)==S_THREAD_LOCAL_ZEROFILL;
                if(!zero) Require(RangeOK(f,sz,d.length),@"损坏的节 / Section bounds");
                [sections addObject:@{@"name":FixedString(d,q,16),@"addr":@(U64(d,q+32)),@"size":@(sz),@"offset":@(f),@"flags":@(flags),@"zero":@(zero)}];
            }
        } else if(cmd==LC_SYMTAB) { Require(len>=24,@"损坏的符号表命令 / Symbol command"); sym=@{@"offset":@(U32(d,off+8)),@"count":@(U32(d,off+12)),@"strings":@(U32(d,off+16)),@"stringSize":@(U32(d,off+20))}; }
        off+=len;
    }
    Require(off==32+bytes,@"加载命令长度不一致 / Load command length mismatch");
    return @{@"segments":segments,@"sections":sections,@"symbols":sym,@"headerEnd":@(off)};
}

static NSUInteger FileOffset(NSDictionary *layout,uint64_t address,NSUInteger size,BOOL code) {
    for(NSDictionary *s in layout[@"sections"]) {
        uint64_t a=[s[@"addr"] unsignedLongLongValue],n=[s[@"size"] unsignedLongLongValue]; BOOL isCode=([s[@"flags"] unsignedIntValue]&(S_ATTR_PURE_INSTRUCTIONS|S_ATTR_SOME_INSTRUCTIONS)) || [s[@"name"] isEqual:@"__text"];
        if(![s[@"zero"] boolValue] && address>=a && size<=n && address-a<=n-size && code==isCode) return [s[@"offset"] unsignedIntegerValue]+(NSUInteger)(address-a);
    }
    Fail(@"目标地址不在预期代码或常量节中 / Address is outside the expected section"); return 0;
}

static NSDictionary *SymbolRanges(NSData *d,NSDictionary *layout) {
    NSDictionary *s=layout[@"symbols"]; Require(s.count>0,@"版本缺少必要符号，停止修改 / Required symbols are missing"); NSUInteger p=[s[@"offset"] unsignedIntegerValue],n=[s[@"count"] unsignedIntegerValue],st=[s[@"strings"] unsignedIntegerValue],ss=[s[@"stringSize"] unsignedIntegerValue];
    Require(n<4000000 && RangeOK(p,n*16,d.length) && RangeOK(st,ss,d.length),@"损坏的符号表 / Invalid symbol table");
    NSMutableArray *values=[NSMutableArray new]; NSMutableDictionary *named=[NSMutableDictionary new];
    for(NSUInteger i=0;i<n;i++) { NSUInteger q=p+i*16; const uint8_t *raw=d.bytes; uint8_t type=raw[q+4]; if((type&N_STAB) || (type&N_TYPE)!=N_SECT) continue; uint32_t si=U32(d,q); Require(si<ss,@"符号名称越界 / Invalid symbol name"); uint64_t address=U64(d,q+8); [values addObject:@(address)]; NSString *name=FixedString(d,st+si,ss-si);
        if([name isEqual:InitSymbol] || [name isEqual:SupportSymbol]) { Require(!named[name],@"必要符号不唯一 / Duplicate required symbol"); named[name]=@(address); }
    }
    Require(named[InitSymbol] && named[SupportSymbol],@"未识别到已支持的 Panasonic 结构；不会尝试盲目修改 / Panasonic rule not recognized");
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSString *key in named) { uint64_t a=[named[key] unsignedLongLongValue],end=UINT64_MAX; for(NSNumber *v in values) if(v.unsignedLongLongValue>a && v.unsignedLongLongValue<end) end=v.unsignedLongLongValue; Require(end>a && end-a<=65536,@"函数范围无法确认 / Function range cannot be established"); NSUInteger off=FileOffset(layout,a,(NSUInteger)(end-a),YES); result[key]=@{@"addr":@(a),@"offset":@(off),@"size":@(end-a)}; }
    return result;
}

static int64_t Signed21(uint32_t x) { return (x&0x100000)?(int64_t)x-0x200000:(int64_t)x; }
static uint64_t PageTarget(uint32_t ins,uint64_t pc) { uint32_t imm=((ins>>5)&0x7ffff)<<2 | ((ins>>29)&3); return (uint64_t)((int64_t)(pc&~0xfffull)+Signed21(imm)*4096); }
static uint64_t LoadTarget(NSData *d,NSUInteger off,uint64_t pc,NSUInteger index,BOOL vector) {
    uint32_t a=U32(d,off+index*4),b=U32(d,off+(index+1)*4); Require((a&0x9f00001f)==0x90000008,@"ADRP 结构不匹配 / ADRP mismatch");
    uint32_t expected=vector?0x3dc00100:0xfd400100; Require((b&0xffc003e0)==expected,@"常量加载结构不匹配 / Constant load mismatch");
    return PageTarget(a,pc+index*4)+((uint64_t)((b>>10)&0xfff))*(vector?16:8);
}

static NSDictionary *Analyze(NSData *whole) {
    NSArray *slices=Slices(whole); NSDictionary *arm=nil; NSMutableArray *architectures=[NSMutableArray new];
    for(NSDictionary *s in slices) { uint32_t cpu=[s[@"cpu"] unsignedIntValue]; [architectures addObject:cpu==CPU_TYPE_ARM64?@"arm64":cpu==CPU_TYPE_X86_64?@"x86_64":[NSString stringWithFormat:@"cpu-%x",cpu]]; if(cpu==CPU_TYPE_ARM64) { Require(!arm,@"多个 arm64 slice / Multiple ARM64 slices"); Require(([s[@"subtype"] unsignedIntValue]&0x00ffffff)==CPU_SUBTYPE_ARM64_ALL,@"暂不支持 arm64e / ARM64e is not supported");arm=s; } }
    Require(arm!=nil,@"需要含 arm64 的 Capture One；本工具尚不为 Intel 相机驱动打补丁 / Requires an ARM64 Capture One build");
    NSUInteger base=[arm[@"offset"] unsignedIntegerValue]; NSData *d=[whole subdataWithRange:NSMakeRange(base,[arm[@"size"] unsignedIntegerValue])]; NSDictionary *layout=Layout(d),*ranges=SymbolRanges(d,layout),*init=ranges[InitSymbol],*support=ranges[SupportSymbol];
    // Rule family v1: validate the complete seven-character XOR initializer,
    // resolve its constants through ARM64 instructions, and prove that the
    // resulting model record is referenced by PanasonicFactory::IsSupported.
    const uint32_t pattern[]={0x90000008,0x3dc00100,0x90000008,0x3dc00101,0xad0187e0,0xf90017ff,0xf94017e8,0x9100c3e9,0x8b080928,0x3dc00100,0x3d8007e0,0xfd400908,0xb9401914,0x52800400,0x94000000,0x90000008,0xfd400100,0x2e201d00,0x90000008,0x3dc00101,0x3dc007e2,0x6e211c41,0x90000008,0x91000108,0xf9000100,0x90000009,0x3dc00122,0x52800009,0x4a090289,0x3c808102,0x3d800001,0xfd000800,0x29037c09};
    const uint32_t masks[]={0x9f00001f,0xffc003ff,0x9f00001f,0xffc003ff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xfc000000,0x9f00001f,0xffc003ff,0xffffffff,0x9f00001f,0xffc003ff,0xffffffff,0xffffffff,0x9f00001f,0xffc003ff,0xffffffff,0x9f00001f,0xffc003ff,0xffe0001f,0xffffffff,0xffffffff,0xffffffff,0xffffffff,0xffffffff};
    NSMutableArray *matches=[NSMutableArray new]; NSUInteger start=[init[@"offset"] unsignedIntegerValue],len=[init[@"size"] unsignedIntegerValue]; uint64_t addr=[init[@"addr"] unsignedLongLongValue];
    for(NSUInteger delta=8;delta+sizeof(pattern)<=len;delta+=4) {
        NSUInteger off=start+delta; BOOL match=YES;
        for(NSUInteger j=0;j<33;j++) if((U32(d,off+j*4)&masks[j])!=pattern[j]) { match=NO;break; }
        if(!match || U32(d,off-8)!=0x52800028 || U32(d,off-4)!=0xb9001928) continue;
        uint64_t pc=addr+delta; uint64_t encAddr=LoadTarget(d,off,pc,0,YES),enc2=LoadTarget(d,off,pc,2,YES),key8Addr=LoadTarget(d,off,pc,15,NO),key16Addr=LoadTarget(d,off,pc,18,YES);
        Require(enc2==encAddr+16,@"型号常量不连续 / Noncontiguous model constants"); NSUInteger enc=FileOffset(layout,encAddr,32,NO),key8=FileOffset(layout,key8Addr,8,NO),key16=FileOffset(layout,key16Addr,16,NO);
        Require(NSMaxRange(NSMakeRange(enc,32))<=key8 || NSMaxRange(NSMakeRange(key8,8))<=enc,@"型号与密钥重叠 / Overlapping constants");
        Require(NSMaxRange(NSMakeRange(enc,32))<=key16 || NSMaxRange(NSMakeRange(key16,16))<=enc,@"型号与密钥重叠 / Overlapping constants");
        uint32_t chars[7]; for(int j=0;j<4;j++) chars[j]=U32(d,enc+j*4)^U32(d,key16+j*4); for(int j=0;j<2;j++) chars[j+4]=U32(d,enc+16+j*4)^U32(d,key8+j*4); chars[6]=U32(d,enc+24)^((U32(d,off+27*4)>>5)&0xffff);
        char model[8]={0}; for(int j=0;j<7;j++) { if(chars[j]>127 || chars[j]<32) match=NO; model[j]=(char)chars[j]; }
        if(!match) continue; NSString *name=[NSString stringWithUTF8String:model]; if(![name isEqual:@"DC-S1M2"] && ![name isEqual:@"DC-S5M2"]) continue;
        uint32_t add=U32(d,off+23*4); uint64_t record=PageTarget(U32(d,off+22*4),pc+22*4)+((add>>10)&0xfff)-8;
        BOOL referenced=NO; NSUInteger so=[support[@"offset"] unsignedIntegerValue],sl=[support[@"size"] unsignedIntegerValue];uint64_t sa=[support[@"addr"] unsignedLongLongValue];
        for(NSUInteger j=0;j+8<=sl;j+=4) { uint32_t a=U32(d,so+j),b=U32(d,so+j+4);uint32_t reg=a&31;
            if((a&0x9f000000)==0x90000000 && (b&0xffc00000)==0x91000000 && (b&31)==reg && ((b>>5)&31)==reg && PageTarget(a,sa+j)+((b>>10)&0xfff)==record) referenced=YES;
        }
        Require(referenced,@"型号记录未被白名单函数引用 / Model is not referenced by whitelist function");
        [matches addObject:@{@"model":name,@"offset":@(base+enc+16),@"sliceOffset":@(enc+16),@"sliceBase":@(base),@"sliceSHA256":SHA(d),@"rule":@"panasonic-xor-arm64-v1"}];
    }
    Require(matches.count==1,matches.count?@"找到多个候选，停止修改 / Ambiguous candidates":@"此版本不匹配已知规则，未修改任何文件 / This build does not match a known rule");
    NSMutableDictionary *result=[matches.firstObject mutableCopy];result[@"architectures"]=architectures;result[@"alreadyPatched"]=@([result[@"model"] isEqual:@"DC-S5M2"]);result[@"testedBinary"]=@([result[@"sliceSHA256"] isEqual:KnownHash]);result[@"target"]=@"DC-S5M2";result[@"binarySHA256"]=SHA(whole);return result;
}

static NSDictionary *Run(NSString *tool,NSArray<NSString *> *args,BOOL mustSucceed) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:tool];task.arguments=args;NSPipe *out=[NSPipe pipe];task.standardOutput=out;task.standardError=out;NSError *error=nil;
    Require([task launchAndReturnError:&error],error.localizedDescription ?: @"无法启动系统工具 / Cannot run system tool");
    NSData *data=[out.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if(mustSucceed && task.terminationStatus) Fail([NSString stringWithFormat:@"%@ 执行失败 / Failed (%d)\n%@",tool.lastPathComponent,task.terminationStatus,s]);
    return @{@"status":@(task.terminationStatus),@"output":s};
}
static NSDictionary *Entitlements(NSURL *app,NSString *arch) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/codesign"];
    task.arguments=@[@"--display",@"--arch",arch,@"--entitlements",@"-",@"--xml",app.path];
    NSPipe *out=[NSPipe pipe];task.standardOutput=out;task.standardError=NSFileHandle.fileHandleWithNullDevice;NSError *error=nil;
    Require([task launchAndReturnError:&error],error.localizedDescription ?: @"无法读取权限 / Cannot read entitlements");
    NSData *data=[out.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];Require(task.terminationStatus==0,@"无法确认原有权限 / Cannot establish existing entitlements");
    if(!data.length)return @{};
    id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
    Require([value isKindOfClass:NSDictionary.class],@"无法解析原有权限，停止修改 / Cannot parse existing entitlements");return value;
}
static NSData *Read(NSURL *url) { NSError *e=nil;NSData *d=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&e];Require(d!=nil,e.localizedDescription);return d; }
static BOOL Inside(NSURL *child,NSURL *parent) { NSString *c=child.URLByResolvingSymlinksInPath.path,*p=parent.URLByResolvingSymlinksInPath.path;return [c hasPrefix:[p stringByAppendingString:@"/"]]; }
static NSURL *Child(NSURL *parent,NSString *path) { return [parent URLByAppendingPathComponent:path]; }
static NSString *BinaryRelative(NSURL *app) {
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *fw=Child(app,@"Contents/Frameworks/P1CaptureCoreObjC.framework"),*binary=Child(fw,@"P1CaptureCoreObjC").URLByResolvingSymlinksInPath;
    Require([fm fileExistsAtPath:binary.path] && Inside(binary,app) && Inside(binary,fw),@"相机框架路径不安全或不存在 / Invalid camera framework path");
    return [binary.path substringFromIndex:app.URLByResolvingSymlinksInPath.path.length+1];
}
static NSDictionary *Inspect(NSURL *app) {
    app=app.URLByResolvingSymlinksInPath;NSDictionary *info=[NSPropertyListSerialization propertyListWithData:Read(Child(app,@"Contents/Info.plist")) options:NSPropertyListImmutable format:nil error:nil];
    Require([info isKindOfClass:NSDictionary.class],@"无效应用信息 / Invalid application info");NSString *bid=info[@"CFBundleIdentifier"],*exe=info[@"CFBundleExecutable"];
    Require(([bid hasPrefix:@"com.captureone.captureone"] || [bid hasPrefix:@"com.phaseone.captureone"]) && [exe isEqual:@"Capture One"],@"请选择 Capture One.app / Select Capture One.app");
    NSString *rel=BinaryRelative(app);NSDictionary *analysis=Analyze(Read(Child(app,rel)));NSMutableDictionary *result=[analysis mutableCopy]; result[@"version"]=info[@"CFBundleShortVersionString"] ?: @"?";result[@"bundleID"]=bid;result[@"binaryRelative"]=rel;result[@"source"]=app.path;
    result[@"testedBuild"]=@([result[@"testedBinary"] boolValue] && [result[@"version"] isEqual:@"16.7.4.24"]);return result;
}
static NSDictionary *ContentFingerprints(NSData *whole) {
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSDictionary *slice in Slices(whole)) {NSData *d=[whole subdataWithRange:NSMakeRange([slice[@"offset"] unsignedIntegerValue],[slice[@"size"] unsignedIntegerValue])];NSDictionary *layout=Layout(d);NSMutableDictionary *segs=[NSMutableDictionary new];
        for(NSDictionary *s in layout[@"segments"]) {if([s[@"name"] isEqual:@"__LINKEDIT"])continue;NSUInteger off=[s[@"offset"] unsignedIntegerValue],end=off+[s[@"size"] unsignedIntegerValue];if(!off)off=[layout[@"headerEnd"] unsignedIntegerValue];Require(end>=off,@"段边界无效 / Segment bounds");segs[s[@"name"]]=SHA([d subdataWithRange:NSMakeRange(off,end-off)]);}
        NSString *key=[NSString stringWithFormat:@"%@:%@",slice[@"cpu"],slice[@"subtype"]];Require(!result[key],@"重复架构 / Duplicate architecture");result[key]=segs;
    }return result;
}
static void CheckWritablePaths(NSURL *app,NSString *binaryRelative) {
    NSArray *paths=@[binaryRelative,@"Contents/MacOS/Capture One",@"Contents/Info.plist",@"Contents/_CodeSignature",@"Contents/Frameworks/P1CaptureCoreObjC.framework/Versions/Current",@"Contents/Frameworks/P1CaptureCoreObjC.framework/Versions/Current/_CodeSignature"];
    for(NSString *rel in paths)Require(Inside(Child(app,rel),app),@"应用包含指向外部的可写路径，停止操作 / External symlink in signing path");
}

@implementation S5PatchCore
+ (NSDictionary *)analyzeBinary:(NSData *)data error:(NSError **)error { @try {return Analyze(data);} @catch(NSException *e){if(error)*error=Error(e);return nil;} }
+ (NSDictionary *)inspectApp:(NSURL *)app error:(NSError **)error { @try {return Inspect(app);} @catch(NSException *e){if(error)*error=Error(e);return nil;} }
+ (NSURL *)createCopy:(NSURL *)source inFolder:(NSURL *)folder progress:(S5Progress)progress error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *stage=nil,*destination=nil;
    @try {
        int armHost=0;size_t armHostSize=sizeof(armHost);sysctlbyname("hw.optional.arm64",&armHost,&armHostSize,NULL,0);
        Require(armHost==1,@"创建 S5M2 副本需要 Apple 芯片 Mac / Creating a compatible copy requires Apple silicon");
        source=source.URLByResolvingSymlinksInPath;folder=folder.URLByResolvingSymlinksInPath;BOOL dir=NO;Require([fm fileExistsAtPath:folder.path isDirectory:&dir]&&dir,@"请选择已有保存文件夹 / Select an existing output folder");
        Require(![folder.path isEqual:source.path]&&!Inside(folder,source),@"保存位置不能在原版应用内 / Output cannot be inside source app");
        progress(@"检查型号规则 / Checking compatibility rule…");NSDictionary *initial=Inspect(source);Require(![initial[@"alreadyPatched"] boolValue],@"此文件已包含 S5M2 补丁 / This binary is already patched");NSString *rel=initial[@"binaryRelative"];CheckWritablePaths(source,rel);
        NSURL *sourceMain=Child(source,@"Contents/MacOS/Capture One");NSString *mainHash=SHA(Read(sourceMain));NSString *infoHash=SHA(Read(Child(source,@"Contents/Info.plist")));
        progress(@"验证原文件签名 / Verifying source signatures…");Run(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",source.path],YES);
        BOOL runtime=NO;
        for(NSDictionary *slice in Slices(Read(sourceMain))) {
            uint32_t cpu=[slice[@"cpu"] unsignedIntValue];NSString *arch=cpu==CPU_TYPE_ARM64?@"arm64":cpu==CPU_TYPE_X86_64?@"x86_64":nil;
            Require(arch!=nil,@"主程序架构尚未审查 / Unreviewed main executable architecture");
            NSDictionary *entValues=Entitlements(source,arch);
            // Local signatures cannot safely retain team-bound account groups.
            for(NSString *key in entValues) if([key containsString:@"keychain-access-groups"] || [key containsString:@"application-groups"] || [key isEqual:@"com.apple.application-identifier"] || [key isEqual:@"application-identifier"] || [key isEqual:@"com.apple.developer.team-identifier"]) Fail(@"此安装使用签名绑定的账号或应用权限。为保护授权，当前版本停止创建副本 / Identity-bound entitlements require a separately reviewed rule");
            NSString *detail=Run(@"/usr/bin/codesign",@[@"-dv",@"--verbose=4",@"--arch",arch,source.path],YES)[@"output"];
            NSRange flagsRange=[detail rangeOfString:@"flags=0x"];unsigned long long flags=0;
            Require(flagsRange.location!=NSNotFound && [[NSScanner scannerWithString:[detail substringFromIndex:NSMaxRange(flagsRange)]] scanHexLongLong:&flags],@"无法读取签名运行标志 / Cannot read signature runtime flags");
            BOOL thisRuntime=(flags&0x10000)!=0;runtime|=thisRuntime;
            Require(!thisRuntime || [entValues[@"com.apple.security.cs.disable-library-validation"] boolValue],@"此安装启用了严格的库验证，当前工具不会降低保护设置；停止创建 / Strict library validation is enabled; no protections will be weakened");
        }
        NSString *token=NSUUID.UUID.UUIDString;NSDateFormatter *df=[NSDateFormatter new];df.dateFormat=@"yyyyMMdd-HHmmss";NSString *name=[NSString stringWithFormat:@"S5M2-%@-%@",[df stringFromDate:NSDate.date],[token substringToIndex:6]];
        stage=Child(folder,[@".s5m2-building-" stringByAppendingString:token]);Require([fm createDirectoryAtURL:stage withIntermediateDirectories:NO attributes:nil error:nil],@"无法创建输出目录 / Cannot create output directory");NSURL *copy=Child(stage,@"Capture One.app");
        progress(@"复制应用；原版保持不变 / Copying application…");Run(@"/usr/bin/ditto",@[source.path,copy.path],YES);CheckWritablePaths(copy,rel);
        Run(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",copy.path],YES);
        Require([SHA(Read(sourceMain)) isEqual:mainHash] && [SHA(Read(Child(source,@"Contents/Info.plist"))) isEqual:infoHash],@"复制期间原版发生变化 / Source changed while copying");
        NSDictionary *check=Inspect(copy);Require([check[@"binarySHA256"] isEqual:initial[@"binarySHA256"]],@"复制文件与源文件不一致 / Copied driver does not match source");
        NSData *before=Read(Child(copy,rel));NSMutableData *patched=[before mutableCopy];NSUInteger offset=[check[@"offset"] unsignedIntegerValue];uint8_t *raw=patched.mutableBytes;raw[offset]^=4;
        NSDictionary *afterPatch=Analyze(patched);Require([afterPatch[@"alreadyPatched"] boolValue],@"修改后型号校验失败 / Patched model validation failed");
        NSUInteger changes=0;const uint8_t *pre=before.bytes;for(NSUInteger i=0;i<before.length;i++)if(pre[i]!=raw[i])changes++;Require(changes==1,@"修改范围异常 / Unexpected patch extent");
        NSDictionary *fingerprints=ContentFingerprints(patched);progress(@"应用单字节补丁 / Applying verified one-byte patch…");NSError *writeError=nil;Require([patched writeToURL:Child(copy,rel) options:NSDataWritingAtomic error:&writeError],writeError.localizedDescription ?: @"无法写入副本 / Cannot write copy");
        progress(@"仅在副本上签名并校验 / Signing and verifying copy…");NSURL *fw=Child(copy,@"Contents/Frameworks/P1CaptureCoreObjC.framework");
        Run(@"/usr/bin/codesign",@[@"--force",@"--sign",@"-",@"--timestamp=none",@"--preserve-metadata=identifier,flags",fw.path],YES);
        Run(@"/usr/bin/codesign",@[@"--force",@"--sign",@"-",@"--timestamp=none",@"--preserve-metadata=identifier,entitlements,flags",copy.path],YES);
        Run(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",copy.path],YES);
        NSData *signedData=Read(Child(copy,rel));Require([fingerprints isEqual:ContentFingerprints(signedData)],@"签名改变了预期以外的代码或数据 / Signing changed protected code or data");Require([Analyze(signedData)[@"alreadyPatched"] boolValue],@"签名后补丁校验失败 / Post-sign patch check failed");
        Require([SHA(Read(Child(source,rel))) isEqual:initial[@"binarySHA256"]] && [SHA(Read(sourceMain)) isEqual:mainHash] && [SHA(Read(Child(source,@"Contents/Info.plist"))) isEqual:infoHash],@"原文件在操作期间发生变化 / Source changed during operation");
        NSMutableDictionary *report=[initial mutableCopy];report[@"toolVersion"]=@"0.1.0";report[@"createdAt"]=[NSISO8601DateFormatter.new stringFromDate:NSDate.date];report[@"sourceMainSHA256"]=mainHash;report[@"resultBinarySHA256"]=SHA(signedData);report[@"oneBytePatch"]=@YES;report[@"architecturesPreserved"]=@YES;report[@"codeDataVerifiedAfterSigning"]=@YES;report[@"originalFilesUnchanged"]=@YES;report[@"captureOneLaunched"]=@NO;report[@"signing"]=@"local-ad-hoc";report[@"runtimePreserved"]=@(runtime);report[@"cameraFunctionsTestedByThisTool"]=@NO;
        NSData *reportData=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];Require([reportData writeToURL:Child(stage,@"Compatibility-Report.json") atomically:YES],@"无法保存报告 / Cannot save report");
        NSString *notes=@"S5M2 Compatibility Tool\n\n此目录中的 Capture One.app 是实验副本。保持这个包名；可以移动整个外层目录。\n本工具没有启动 Capture One，也没有连接或操作相机。\n请先退出其他 Capture One 实例，并使用新建测试会话进行验证。\n规则匹配不等于本版本已通过实机测试。副本采用本地签名，账号或登录兼容性须另行验证。\n原版、用户设置、钥匙串和相机设置均未被本工具修改。\n不要通过关闭 SIP 或全局安全检查来解决启动问题。\n\nThis is an experimental copy. Keep the inner app name Capture One.app.\nA matching patch rule does not establish camera compatibility for this build.\nThe tool does not launch Capture One or send camera commands.\nThe installed application and user data are untouched.\n";
        Require([notes writeToURL:Child(stage,@"请先阅读-Read-Me.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil],@"无法保存说明 / Cannot save instructions");destination=Child(folder,name);Require([fm moveItemAtURL:stage toURL:destination error:&writeError],writeError.localizedDescription ?: @"无法完成副本 / Cannot finalize copy");stage=nil;progress(@"副本创建完成 / Copy is ready");return destination;
    }@catch(NSException *e){if(stage)[fm removeItemAtURL:stage error:nil];if(error)*error=Error(e);return nil;}
}
@end
