// WatchBothNotify v1.0.1 链路细分计数版（过渡探针，使命完成即删）
// 目的：分清 iOS16 实际调用的是变体 A（WinterMode 原版 8 参）还是变体 B（iOS15+ 精简 6 参）
//   —— 1.0.0 的合并计数分不出，本版两条各自首次命中写各自标记：
//   /tmp/wbn_hitA.log 出现 = 系统走 8 参老签名
//   /tmp/wbn_hitB.log 出现 = 系统走 6 参精简签名
//   （两个都没出现 = 两条都没被调，需要重挖；都出现 = 两条都走，正式版都得留）
// 行为与 1.0.0 完全一致（双变体都强改 NO，双响不中断），只多两个首次命中标记。
// daemon 视角 /tmp = /private/var/tmp；SSH 读加 /rootfs/private 前缀。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdatomic.h>
#include <time.h>

// 首次命中即写（覆写带 pid+时间戳，不随调用涨）
static void wbnMark(const char *path) {
    char buf[128];
    snprintf(buf, sizeof(buf), "hit at %ld pid=%d\n", (long)time(NULL), getpid());
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { (void)write(fd, buf, strlen(buf)); close(fd); }
}

static atomic_bool wbnAHit = false;
static atomic_bool wbnBHit = false;

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
    if (!atomic_exchange(&wbnAHit, true)) wbnMark("/tmp/wbn_hitA.log");
    didPlay = NO;
    %orig;
}

// 变体 B：iOS 15+ 精简版（iOS16 探针实锤共存，args=7）
- (void)_handleDidPlayLightsAndSirens:(BOOL)didPlay
                           forBulletin:(id)bulletin
                        inPhoneSection:(id)phoneSection
                            finalReply:(BOOL)finalReply
                            replyToken:(id)replyToken {
    if (!atomic_exchange(&wbnBHit, true)) wbnMark("/tmp/wbn_hitB.log");
    didPlay = NO;
    %orig;
}

%end
