#import <Cocoa/Cocoa.h>
#import "PatchCore.h"

static NSString *L(NSString *zh,NSString *en) { return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"]?zh:en; }
static NSTextField *Label(NSString *text,CGFloat size,BOOL bold) { NSTextField *v=[NSTextField wrappingLabelWithString:text];v.font=bold?[NSFont systemFontOfSize:size weight:NSFontWeightSemibold]:[NSFont systemFontOfSize:size];return v; }
static NSButton *Button(NSString *title,id target,SEL action) {NSButton *b=[NSButton buttonWithTitle:title target:target action:action];b.bezelStyle=NSBezelStyleRounded;return b;}

@interface AppDelegate : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *sourceLabel,*folderLabel,*statusLabel,*detailLabel;
@property NSButton *chooseButton,*folderButton,*createButton,*revealButton,*experimental;
@property NSProgressIndicator *spinner;
@property NSTextView *logView;
@property NSURL *source,*folder,*result;
@property NSDictionary *inspection;
@property BOOL busy;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.folder=[NSFileManager.defaultManager URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask].firstObject;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,790,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"S5M2 Compatibility Tool";self.window.delegate=self;[self.window center];
    NSView *content=self.window.contentView;
    NSStackView *stack=[NSStackView new];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:30],[stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-30],[stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:25]]];
    [stack addArrangedSubview:Label(L(@"让 S5M2 连接 Capture One",@"Connect your S5M2 to Capture One"),26,YES)];
    NSTextField *sub=Label(L(@"创建一个独立兼容副本，原版应用保持不变。",@"Create a separate compatibility copy. Your installed app stays unchanged."),14,NO);sub.textColor=NSColor.secondaryLabelColor;[stack addArrangedSubview:sub];
    NSBox *line=[NSBox new];line.boxType=NSBoxSeparator;[stack addArrangedSubview:line];[line.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    [stack addArrangedSubview:Label(L(@"1  选择你的 Capture One",@"1  Choose your Capture One"),15,YES)];
    self.chooseButton=Button(L(@"选择应用…",@"Choose app…"),self,@selector(chooseSource:));self.sourceLabel=Label(L(@"尚未选择",@"No app selected"),12,NO);self.sourceLabel.textColor=NSColor.secondaryLabelColor;
    NSStackView *row=[NSStackView stackViewWithViews:@[self.chooseButton,self.sourceLabel]];row.spacing=12;row.orientation=NSUserInterfaceLayoutOrientationHorizontal;[stack addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.statusLabel=Label(L(@"等待检查",@"Ready to inspect"),16,YES);[stack addArrangedSubview:self.statusLabel];
    self.detailLabel=Label(L(@"支持 Apple 芯片 Mac。自动识别可用的型号补丁规则；无法确认的版本会停止修改。",@"For Apple silicon Macs. The tool checks the model rule before changing any copy."),13,NO);self.detailLabel.textColor=NSColor.secondaryLabelColor;[stack addArrangedSubview:self.detailLabel];[self.detailLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.experimental=[NSButton checkboxWithTitle:L(@"我理解：此版本仅匹配规则，尚未经过实机验证",@"I understand: this build matches a rule but has not been camera-tested") target:self action:@selector(updateButtons)];self.experimental.hidden=YES;[stack addArrangedSubview:self.experimental];
    [stack addArrangedSubview:Label(L(@"2  选择副本保存位置",@"2  Choose where to save the copy"),15,YES)];
    self.folderButton=Button(L(@"选择文件夹…",@"Choose folder…"),self,@selector(chooseFolder:));self.folderLabel=Label(self.folder.path,12,NO);self.folderLabel.textColor=NSColor.secondaryLabelColor;
    NSStackView *folders=[NSStackView stackViewWithViews:@[self.folderButton,self.folderLabel]];folders.spacing=12;[stack addArrangedSubview:folders];[folders.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    NSTextField *boundary=Label(L(@"副本采用本地签名，某些安装的登录或授权可能不适用于副本。工具不会修改账号信息或降低系统保护，也不会启动应用或操作相机。",@"Copies use local signatures; login or licensing may not work with every installation. The tool does not modify account data, weaken system protections, launch Capture One or operate the camera."),12,NO);boundary.textColor=NSColor.secondaryLabelColor;[stack addArrangedSubview:boundary];[boundary.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    self.createButton=Button(L(@"创建兼容副本",@"Create compatibility copy"),self,@selector(createCopy:));self.createButton.bezelColor=NSColor.controlAccentColor;self.createButton.keyEquivalent=@"\r";
    self.revealButton=Button(L(@"在 Finder 中查看",@"Show in Finder"),self,@selector(reveal:));self.revealButton.hidden=YES;
    self.spinner=[NSProgressIndicator new];self.spinner.style=NSProgressIndicatorStyleSpinning;self.spinner.controlSize=NSControlSizeSmall;self.spinner.displayedWhenStopped=NO;
    NSStackView *actions=[NSStackView stackViewWithViews:@[self.createButton,self.spinner,self.revealButton]];actions.spacing=12;[stack addArrangedSubview:actions];
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.borderType=NSBezelBorder;self.logView=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,700,130)];self.logView.editable=NO;self.logView.selectable=YES;self.logView.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];scroll.documentView=self.logView;[stack addArrangedSubview:scroll];[scroll.heightAnchor constraintEqualToConstant:125].active=YES;[scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    [stack addArrangedSubview:Label(L(@"0.1.0 · 离线运行 · 多版本规则识别 · 非 Capture One 官方工具",@"0.1.0 · Offline · Version-aware rules · Independent, unofficial tool"),11,NO)];
    [self appendLog:L(@"选择应用后先检查；检查不会写入文件。",@"Choose an app to inspect it. Inspection does not write to files.")];
    [self updateButtons];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    NSMenu *menu=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[menu addItem:root];NSMenu *appMenu=[NSMenu new];[appMenu addItemWithTitle:L(@"退出 S5M2 Compatibility Tool",@"Quit S5M2 Compatibility Tool") action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=appMenu;
    NSMenuItem *editRoot=[[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];[menu addItem:editRoot];NSMenu *edit=[NSMenu new];[edit addItemWithTitle:L(@"复制",@"Copy") action:@selector(copy:) keyEquivalent:@"c"];[edit addItemWithTitle:L(@"全选",@"Select All") action:@selector(selectAll:) keyEquivalent:@"a"];editRoot.submenu=edit;NSApp.mainMenu=menu;
}
- (void)appendLog:(NSString *)text { NSString *line=[text stringByAppendingString:@"\n"];[self.logView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:@{NSFontAttributeName:self.logView.font,NSForegroundColorAttributeName:NSColor.textColor}]];[self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length,0)]; }
- (void)updateButtons {BOOL ready=self.inspection && ![self.inspection[@"alreadyPatched"] boolValue] && ([self.inspection[@"testedBuild"] boolValue] || self.experimental.state==NSControlStateValueOn);self.createButton.enabled=!self.busy && ready;self.chooseButton.enabled=!self.busy;self.folderButton.enabled=!self.busy;self.experimental.enabled=!self.busy;}
- (void)setWorking:(BOOL)working {self.busy=working;if(working)[self.spinner startAnimation:nil];else[self.spinner stopAnimation:nil];[self updateButtons];}
- (void)chooseSource:(id)sender {NSOpenPanel *p=[NSOpenPanel openPanel];p.canChooseDirectories=NO;p.canChooseFiles=YES;p.treatsFilePackagesAsDirectories=NO;p.allowsMultipleSelection=NO;p.directoryURL=[NSURL fileURLWithPath:@"/Applications"];p.message=L(@"选择你已安装的 Capture One.app",@"Choose your installed Capture One.app");[p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;self.source=p.URL;self.sourceLabel.stringValue=self.source.path;self.result=nil;self.revealButton.hidden=YES;self.inspection=nil;self.experimental.hidden=YES;self.experimental.state=NSControlStateValueOff;self.statusLabel.stringValue=L(@"正在检查…",@"Inspecting…");[self setWorking:YES];NSURL *selected=self.source;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=[S5PatchCore inspectApp:selected error:&error];dispatch_async(dispatch_get_main_queue(),^{self.inspection=result;[self setWorking:NO];if(!result){self.statusLabel.stringValue=L(@"此版本暂不支持",@"This build is not supported yet");self.detailLabel.stringValue=error.localizedDescription;[self appendLog:error.localizedDescription];return;}NSString *version=result[@"version"];BOOL already=[result[@"alreadyPatched"] boolValue],tested=[result[@"testedBuild"] boolValue];self.statusLabel.stringValue=already?L(@"已包含 S5M2 补丁",@"Already patched for S5M2"):tested?L(@"已匹配：有实机测试记录的版本",@"Matched: a camera-tested build"):L(@"已匹配规则：此版本尚未实机验证",@"Rule matched: build not camera-tested");self.experimental.hidden=tested||already;self.detailLabel.stringValue=[NSString stringWithFormat:L(@"Capture One %@ · %@\n%@",@"Capture One %@ · %@\n%@"),version,[result[@"architectures"] componentsJoinedByString:@" + "],already?L(@"无需重复修改。",@"No further patch is needed."):L(@"将用 DC-S5M2 替换副本中的 DC-S1M2 白名单项。副本中 S1M2 的这一支持项会被占用。",@"Replaces the copy’s DC-S1M2 whitelist entry with DC-S5M2. This entry will no longer cover the S1M2 in the copy.")];[self appendLog:[NSString stringWithFormat:@"%@ · %@ · %@",version,result[@"rule"],result[@"sliceSHA256"]]];[self updateButtons];});});}];}
- (void)chooseFolder:(id)sender {NSOpenPanel *p=[NSOpenPanel openPanel];p.canChooseFiles=NO;p.canChooseDirectories=YES;p.canCreateDirectories=YES;p.directoryURL=self.folder;[p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK){self.folder=p.URL;self.folderLabel.stringValue=self.folder.path;}}];}
- (void)createCopy:(id)sender {if(!self.createButton.enabled)return;[self setWorking:YES];self.revealButton.hidden=YES;self.statusLabel.stringValue=L(@"正在创建独立副本…",@"Creating a separate copy…");NSURL *source=self.source,*folder=self.folder;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSURL *result=[S5PatchCore createCopy:source inFolder:folder progress:^(NSString *message){dispatch_async(dispatch_get_main_queue(),^{[self appendLog:message];});} error:&error];dispatch_async(dispatch_get_main_queue(),^{[self setWorking:NO];if(result){self.result=result;self.statusLabel.stringValue=L(@"兼容副本已创建",@"Your compatibility copy is ready");self.detailLabel.stringValue=L(@"已核对原文件未变、型号修改正确，副本签名校验通过。请阅读副本旁的说明，并使用单独的测试会话验证。",@"Source files are unchanged, the model patch is verified, and the copy passes signature checks. Read the included notes and use a separate test session.");self.revealButton.hidden=NO;[self appendLog:result.path];}else{self.statusLabel.stringValue=L(@"创建已停止，原版未被本工具修改",@"Creation stopped; the tool did not modify the source");self.detailLabel.stringValue=error.localizedDescription;[self appendLog:error.localizedDescription];}});});}
- (void)reveal:(id)sender {if(self.result)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.result]];}
- (BOOL)windowShouldClose:(NSWindow *)window {if(self.busy){NSBeep();return NO;}return YES;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {if(self.busy){NSBeep();return NSTerminateCancel;}return NSTerminateNow;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {return YES;}
@end

static int PrintJSON(id object) {NSError *e=nil;NSData *d=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&e];if(!d)return 2;fwrite(d.bytes,1,d.length,stdout);fputc('\n',stdout);return 0;}
int main(int argc,const char *argv[]) {@autoreleasepool{
    if(argc>=3 && strcmp(argv[1],"--analyze-binary")==0){NSError *e=nil;NSData *d=[NSData dataWithContentsOfFile:@(argv[2])];NSDictionary *r=d?[S5PatchCore analyzeBinary:d error:&e]:nil;return PrintJSON(r ?: @{@"error":e.localizedDescription ?: @"Cannot read file",@"ok":@NO}) || (r?0:1);}
    if(argc>=3 && strcmp(argv[1],"--inspect")==0){NSError *e=nil;NSDictionary *r=[S5PatchCore inspectApp:[NSURL fileURLWithPath:@(argv[2])] error:&e];return PrintJSON(r ?: @{@"error":e.localizedDescription,@"ok":@NO}) || (r?0:1);}
    if(argc==4 && strcmp(argv[1],"--create")==0){NSError *e=nil;NSURL *r=[S5PatchCore createCopy:[NSURL fileURLWithPath:@(argv[2])] inFolder:[NSURL fileURLWithPath:@(argv[3])] progress:^(NSString *s){fprintf(stderr,"%s\n",s.UTF8String);} error:&e];return PrintJSON(r?@{@"output":r.path,@"ok":@YES}:@{@"error":e.localizedDescription,@"ok":@NO}) || (r?0:1);}
    if(argc>1){fprintf(stderr,"Usage: S5M2Compatibility [--inspect APP | --analyze-binary FILE | --create APP OUTPUT_FOLDER]\n");return 2;}
    NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyRegular];AppDelegate *delegate=[AppDelegate new];app.delegate=delegate;[app run];return 0;
}}
