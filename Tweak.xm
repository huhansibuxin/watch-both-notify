// WatchBothNotify 探针版 v0.0.1（使命完成即删）
// 目的：验证 iOS16 bulletindistributod 进程内 BLTBulletinDistributor 的
//       手表通知去重 hook 点（WinterMode 原版选择器）是否存活、签名是否一致。
// 机制背景（WinterMode for Apple Watch / aydenp/WinterMode 源码级实锤）：
//   iOS 通知路由去重判断在 bulletindistributod（非 SpringBoard）。手表放过提示后
//   系统调 BLTBulletinDistributor._handleDidPlayLightsAndSirens:...(didPlay=YES)
//   → 压制手机。强改 NO → 手机也放 → 手表手机双响。手表侧链路独立不受影响。
// 本版零风险：只读 runtime 元数据 + 写一次日志，不 hook 任何方法。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <fcntl.h>

// 日志：进程内标准路径（root 进程可写）；SSH 侧读要加 /rootfs/private 前缀。
// 覆写模式（O_TRUNC）——daemon 若崩溃重启循环也不会无限涨日志，只保留最新一次。
static void WBNWrite(NSString *text) {
    @autoreleasepool {
        NSString *path = @"/var/mobile/Library/Logs/WatchBothNotify.log";
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            (void)write(fd, data.bytes, data.length);
            close(fd);
        }
    }
}

%ctor {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"=== WatchBothNotify probe v0.0.1 loaded pid=%d ===\n", getpid()];

        Class cls = NSClassFromString(@"BLTBulletinDistributor");
        if (!cls) {
            [out appendString:@"FATAL: BLTBulletinDistributor NOT registered in this process\n"];
            WBNWrite(out);
            return;
        }
        [out appendFormat:@"OK: BLTBulletinDistributor = %p (super=%@)\n", cls, NSStringFromClass(class_getSuperclass(cls))];

        // ① WinterMode 原版完整选择器（iOS 13/14 签名，8 个显式参数）
        SEL origSel = sel_registerName("_handleDidPlayLightsAndSirens:forBulletin:inPhoneSection:transmissionDate:receptionDate:fromGizmo:finalReply:replyToken:");
        Method m = class_getInstanceMethod(cls, origSel);
        if (m) {
            [out appendFormat:@"OK: WinterMode orig selector FOUND args=%u (期望 10 = self+_cmd+8)\n",
                  (unsigned)method_getNumberOfArguments(m)];
            // 打 TypeEncoding，看返回类型与参数类型是否还是 (void)+BOOL 起手
            const char *te = method_getTypeEncoding(m);
            if (te) [out appendFormat:@"    typeEncoding=%s\n", te];
        } else {
            [out appendString:@"MISS: WinterMode orig selector NOT found —— iOS16 签名已变，需按下一条 HIT 列表重定\n"];
        }

        // ② 全量扫实例方法：含 Sirens/Gizmo/Wrist 的都打出来（含参数个数）
        unsigned int count = 0;
        Method *mlist = class_copyMethodList(cls, &count);
        [out appendFormat:@"total instance methods: %u\n", count];
        for (unsigned i = 0; i < count; i++) {
            SEL s = method_getName(mlist[i]);
            NSString *nm = [NSString stringWithUTF8String:sel_getName(s)];
            if ([nm containsString:@"Sirens"] || [nm containsString:@"Gizmo"] || [nm containsString:@"Wrist"]) {
                [out appendFormat:@"  HIT: %@ (args=%u)\n", nm, (unsigned)method_getNumberOfArguments(mlist[i])];
            }
        }
        free(mlist);

        // ③ 类方法也扫（+ sharedDistributor 之类的工厂可能在类方法）
        mlist = class_copyMethodList(object_getClass(cls), &count);
        for (unsigned i = 0; i < count; i++) {
            SEL s = method_getName(mlist[i]);
            NSString *nm = [NSString stringWithUTF8String:sel_getName(s)];
            if ([nm containsString:@"Sirens"] || [nm containsString:@"Gizmo"] || [nm containsString:@"shared"]) {
                [out appendFormat:@"  CLASS-HIT: %@\n", nm];
            }
        }
        free(mlist);

        WBNWrite(out);
    }
}
