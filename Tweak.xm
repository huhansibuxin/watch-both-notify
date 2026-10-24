// WatchBothNotify v1.1.0 正式版（终版）
//
// 功能：戴表时让通知在 Apple Watch 和 iPhone 上同时响（双响）。
//
// 机制（iOS16 实锤）：
//   iOS 的通知去重发生在 bulletindistributord（BLTBulletinDistributor）。
//   手表响铃后会经
//     _handleDidPlayLightsAndSirens:forBulletin:inPhoneSection:transmissionDate:
//     receptionDate:fromGizmo:finalReply:replyToken:
//   向 distributor 回报 didPlay=YES，distributor 据此认为"手表已响"，
//   于是不让手机再响。把 didPlay 强改 NO → 系统认为手表没响 → 手机也响。
//   手表侧送达是独立的 APNs+IDS 链，不受本 hook 影响。
//
// 链路实锤（v1.0.1 细分探针，iOS16 实机）：
//   - 8 参老签名（WinterMode 原版）：被实际调用（/tmp/wbn_hitA.log 命中）。
//   - iOS15+ 6 参精简签名：类里存在但从未被调用（/tmp/wbn_hitB.log 零命中）。
//   → 正式版只保留 8 参这一条，冗余变体已删。
//
// 零日志、零探针、无设置、无定时器：hook 只在系统回调时触发。
//
// 性能特性（不卡主线程、不耗 CPU）：
//   - 事件驱动：只在系统回调本方法时触发（每条通知至多一次），无轮询无定时器。
//   - 回调内只做一次寄存器赋值（didPlay = NO），无 IO、无锁、无堆分配、无额外 ObjC 消息。
//   - %orig 即系统原本要执行的调用，hook 本身不增加任何消息发送。
//   - 注入范围仅 bulletindistributord 单进程（Filter plist 限定），其他进程零成本。

#import <Foundation/Foundation.h>

%hook BLTBulletinDistributor

// iOS16 实际命中的唯一链路：手表响铃后的 didPlay 回报
- (void)_handleDidPlayLightsAndSirens:(BOOL)didPlay
                           forBulletin:(id)bulletin
                        inPhoneSection:(id)phoneSection
                     transmissionDate:(id)transmissionDate
                        receptionDate:(id)receptionDate
                             fromGizmo:(BOOL)fromGizmo
                            finalReply:(BOOL)finalReply
                            replyToken:(id)replyToken {
    didPlay = NO;   // 强制"手表未响" → 手机同时响，实现双响
    %orig;
}

%end
