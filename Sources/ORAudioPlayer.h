#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ORAudioPlayerDidChangeNotification;
extern NSNotificationName const ORAudioPlayerDidFinishNotification;

/// Process-wide audio player: keeps playing when the player screen is closed,
/// integrates with the lock screen and Control Center.
@interface ORAudioPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL hasTrack;
@property (nonatomic, readonly, nullable) NSString *currentBookID;
@property (nonatomic, readonly, nullable) NSString *title;
@property (nonatomic, readonly, nullable) NSString *author;
@property (nonatomic, readonly) double currentTime;
@property (nonatomic, readonly) double duration;
@property (nonatomic) float rate;
@property (nonatomic, readonly) NSInteger sleepMinutesRemaining;

- (void)playURL:(NSURL *)url
          title:(NSString *)title
         author:(nullable NSString *)author
         bookID:(nullable NSString *)bookID
        headers:(nullable NSDictionary<NSString *, NSString *> *)headers;

- (void)play;
- (void)pause;
- (void)toggle;
- (void)seekToTime:(double)time;
- (void)skip:(double)delta;
- (void)stop;

- (void)startSleepTimerWithMinutes:(NSInteger)minutes;
- (void)cancelSleepTimer;

@end

NS_ASSUME_NONNULL_END
