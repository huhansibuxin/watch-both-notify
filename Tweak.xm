// WatchBothNotify v1.0.0 正式版——iPhone + Apple Watch 通知双响
// 机制（WinterMode for Apple Watch / aydenp/WinterMode 源码级 + 本机 iOS16 探针实锤）：
//   iOS 通知路由去重判断在 bulletindistributord（非 SpringBoard）。手表放过提示后
//   系统调 BLTBulletinDistributor._handleDidPlayLightsAndSirens:...(didPlay=YES)
//   → 压制手机。强改 NO → 系统以为手表没放过 → 手机也放 → 双响。
//   手表收通知是独立链路（APNs+IDS 直推），不经过此判断，照常震。
// iOS16 探针实锤（v0.0.2）：原版 8 参选择器 args=10 签名
//   v68@0:8B16@20@28@36@44B52B56@60（void + BOOL didPlay + 5 id + BOOL fromGizmo
//   + BOOL finalReply + id replyToken）与 WinterMode 2020 年原版一字不差；
//   另发现 iOS15+ 精简变体（6 显式参数，无 transmissionDate/receptionDate/fromGizmo）
//   ——两个变体都 hook，系统走哪条都能拦。
// 常开无设置（老板指定）。注入进程：bulletindistributord 单进程。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>

// 命中标记：第 1/10/100 次 hook 命中时覆写 /tmp/wbn_hits.log。
// 作用 = 给实机排障证明"hook 真被调用了"（/tmp 在 daemon 视角 = /private/var/tmp，
// 探针期实证可写；/var/mobile 在 remap + uid=501 下不可写，故不用）。
// 覆写模式：daemon 崩溃重启循环也不会无限涨，只保留最近一次里程碑。
static unsigned long long wbnHits = 0;
static void wbnNoteHit(void) {
    unsigned long long n = ++wbnHits;
    if (n == 1 || n == 10 || n == 100) {
        char buf[128];
        snprintf(buf, sizeof(buf), "WBN hook hit #%llu at %ld\n", n, (long)time(NULL));
        int fd = open("/tmp/wbn_hits.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) { (void)write(fd, buf, strlen(buf)); close(fd); }
    }
}

%hook BLTBulletinDistributor

// 变体 A：WinterMode 原版（iOS 13/14 签名，iOS16 探针实锤存活 args=10）
- (void)_handleDidPlayLightsAndSirens:(BOOL)didPlay
                           forBulletin:(id)bulletin
                        inPhoneSection:(id)phoneSection
                     transmissionDate:(id)transmissionDate
                        receptionDate:(id)receptionDate
                             fromGizmo:(BOOL)fromGizmo
                            finalReply:(BOOL)finalReply
                            replyToken:(id)replyToken {
    wbnNoteHit();
    didPlay = NO;   // ← 核心：系统以为手表没放过提示 → 手机也放
    %orig;
}

// 变体 B：iOS 15+ 精简版（探针实锤共存，args=7，无日期/fromGizmo 三参）
- (void)_handleDidPlayLightsAndSirens:(BOOL)didPlay
                           forBulletin:(id)bulletin
                        inPhoneSection:(id)phoneSection
                            finalReply:(BOOL)finalReply
                            replyToken:(id)replyToken {
    wbnNoteHit();
    didPlay = NO;
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        // 装载自检：类不在就留标记（说明 iOS 大版本又改了布局，排障用）
        if (!NSClassFromString(@"BLTBulletinDistributor")) {
            int fd = open("/tmp/wbn_class_missing", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                const char *msg = "BLTBulletinDistributor NOT registered\n";
                (void)write(fd, msg, strlen(msg));
                close(fd);
            }
        }
    }
}
