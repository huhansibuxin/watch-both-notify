// WatchBothNotify 探针版 v0.0.2（使命完成即删）
// 目的：验证 iOS16 bulletindistributord 进程内 BLTBulletinDistributor 的
//       手表通知去重 hook 点（WinterMode 原版选择器）是否存活、签名是否一致。
// 机制背景（WinterMode for Apple Watch / aydenp/WinterMode 源码级实锤）：
//   iOS 通知路由去重判断在 bulletindistributord（非 SpringBoard）。手表放过提示后
//   系统调 BLTBulletinDistributor._handleDidPlayLightsAndSirens:...(didPlay=YES)
//   → 压制手机。强改 NO → 手机也放 → 手表手机双响。手表侧链路独立不受影响。
// 本版零风险：只读 runtime 元数据 + 写一次日志，不 hook 任何方法。
//
// v0.0.2 排障增强（v0.0.1 实机：CocoaTop 确认 dylib 已加载但日志零输出）：
//   ① 纯 C 层 /tmp 必写标记（先于一切 ObjC）——确认 ctor 到底跑没跑
//   ② 多路径落点尝试 + errno 记录——定位 open 被谁打死
//   ③ syslog 全程输出——不依赖文件路径，log show 直接读

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

// v0.0.2：纯 C 写文件（不依赖 ObjC 运行时，ctor 最开头就能调）
static void wbn_c_write(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        (void)write(fd, text, strlen(text));
        close(fd);
    }
}

// v0.0.2：把报告写遍所有候选路径，第一个成功的即止；全失败写 /tmp 兜底
// （记录每个路径的 errno——daemon 环境里 /var/mobile 的 open 可能被 remap 打飞）
static void WBNWrite(NSString *text) {
    @autoreleasepool {
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        const char *paths[] = {
            "/var/mobile/Library/Logs/WatchBothNotify.log",
            "/tmp/WatchBothNotify.log",
            "/private/var/mobile/Library/Logs/WatchBothNotify.log",
            NULL
        };
        for (int i = 0; paths[i]; i++) {
            int fd = open(paths[i], O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                (void)write(fd, data.bytes, data.length);
                close(fd);
                syslog(LOG_ERR, "[WBN] report written to %s", paths[i]);
                return;
            }
            syslog(LOG_ERR, "[WBN] open FAILED %s errno=%d (%s)", paths[i], errno, strerror(errno));
        }
        // 全失败：兜底写 /tmp（root 进程一定可写）+ syslog 全文
        wbn_c_write("/tmp/wbn_probe_fallback.log", [text UTF8String]);
        syslog(LOG_ERR, "[WBN] all paths failed, fallback to /tmp; report head: %.200s", [text UTF8String]);
    }
}

%ctor {
    // v0.0.2 第一步：纯 C 标记，先于一切 ObjC 调用——证明 ctor 真的执行了
    char entered[64];
    snprintf(entered, sizeof(entered), "ctor entered pid=%d uid=%d\n", getpid(), getuid());
    wbn_c_write("/tmp/wbn_probe_entered", entered);
    syslog(LOG_ERR, "[WBN] %s", entered);

    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"=== WatchBothNotify probe v0.0.2 loaded pid=%d ===\n", getpid()];

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
