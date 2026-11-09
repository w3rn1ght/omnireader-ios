#import "ORAudioPlayer.h"
#import "ORCore.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSNotificationName const ORAudioPlayerDidChangeNotification = @"ORAudioPlayerDidChangeNotification";
NSNotificationName const ORAudioPlayerDidFinishNotification = @"ORAudioPlayerDidFinishNotification";

@interface ORAudioPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy, nullable) NSString *currentBookID;
@property (nonatomic) double duration;
@property (nonatomic) double lastSavedTime;
@property (nonatomic) BOOL restorePending;
@property (nonatomic) float pendingRestoreFraction;
@property (nonatomic, strong) NSTimer *sleepTimer;
@property (nonatomic) NSInteger sleepMinutesRemaining;
@property (nonatomic) BOOL observedCurrentItem;
@end

@implementation ORAudioPlayer

+ (instancetype)shared {
    static ORAudioPlayer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ORAudioPlayer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rate = 1.0;
        _duration = 0;
        _sleepMinutesRemaining = 0;
        [self configureRemoteCommands];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (BOOL)hasTrack {
    return self.player != nil;
}

- (BOOL)isPlaying {
    return self.player.rate > 0.01;
}

- (double)currentTime {
    if (!self.player) return 0;
    double value = CMTimeGetSeconds(self.player.currentTime);
    return isfinite(value) ? value : 0;
}

- (void)playURL:(NSURL *)url
          title:(NSString *)title
         author:(NSString *)author
         bookID:(NSString *)bookID
        headers:(NSDictionary<NSString *, NSString *> *)headers {
    [self stop];

    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];

    AVURLAsset *asset = nil;
    if (headers.count > 0) {
        asset = [AVURLAsset URLAssetWithURL:url options:@{@"AVURLAssetHTTPHeaderFieldsKey": headers}];
    } else {
        asset = [AVURLAsset URLAssetWithURL:url options:nil];
    }
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain;
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.automaticallyWaitsToMinimizeStalling = YES;
    self.title = title;
    self.author = author;
    self.currentBookID = bookID;
    self.duration = 0;
    self.lastSavedTime = 0;
    self.restorePending = YES;
    self.pendingRestoreFraction = 0;

    ORBook *book = bookID ? [[ORLibrary shared] bookWithID:bookID] : nil;
    if (book) {
        self.pendingRestoreFraction = MAX(0, MIN(1, book.progress));
    }

    [self observeCurrentItem:item];
    [self installTimeObserver];
    [self updateNowPlaying];

    [self.player play];
    self.player.rate = self.rate;
    [self notify];
}

- (void)observeCurrentItem:(AVPlayerItem *)item {
    if (self.observedCurrentItem && self.player.currentItem) {
        @try {
            [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
        }
    }
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    self.observedCurrentItem = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
}

- (void)installTimeObserver {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        double current = strongSelf.currentTime;
        if (strongSelf.duration <= 0) {
            CMTime duration = strongSelf.player.currentItem.duration;
            if (CMTIME_IS_NUMERIC(duration)) strongSelf.duration = CMTimeGetSeconds(duration);
        }
        if (strongSelf.currentBookID && strongSelf.duration > 0 && fabs(current - strongSelf.lastSavedTime) > 10) {
            strongSelf.lastSavedTime = current;
            double fraction = MAX(0, MIN(1, current / strongSelf.duration));
            [[ORLibrary shared] setProgress:fraction forBookID:strongSelf.currentBookID];
        }
        [strongSelf updateNowPlaying];
        [strongSelf notify];
        if (strongSelf.sleepMinutesRemaining > 0) {
            [strongSelf updateSleepCountdown];
        }
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            CMTime duration = item.duration;
            if (CMTIME_IS_NUMERIC(duration)) self.duration = CMTimeGetSeconds(duration);
            if (self.restorePending && self.duration > 1) {
                self.restorePending = NO;
                if (self.pendingRestoreFraction > 0.001 && self.pendingRestoreFraction < 0.999) {
                    [self.player seekToTime:CMTimeMakeWithSeconds(self.pendingRestoreFraction * self.duration, NSEC_PER_SEC)];
                }
            }
            [self updateNowPlaying];
            [self notify];
        } else if (item.status == AVPlayerItemStatusFailed) {
            NSLog(@"[OmniReader] audio item failed: %@", item.error);
            [self notify];
        }
    }
}

#pragma mark - Controls

- (void)play {
    if (!self.player) return;
    [self.player play];
    self.player.rate = self.rate;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];
    [self updateNowPlaying];
    [self notify];
}

- (void)pause {
    [self.player pause];
    [self updateNowPlaying];
    [self notify];
    [self persistProgress];
}

- (void)toggle {
    if (self.isPlaying) [self pause];
    else [self play];
}

- (void)seekToTime:(double)time {
    if (!self.player || self.duration <= 0) return;
    double target = MAX(0, MIN(self.duration - 0.2, time));
    [self.player seekToTime:CMTimeMakeWithSeconds(target, NSEC_PER_SEC)
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
    [self updateNowPlaying];
    [self notify];
}

- (void)skip:(double)delta {
    [self seekToTime:self.currentTime + delta];
}

- (void)stop {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.player = nil;
    self.title = nil;
    self.author = nil;
    self.currentBookID = nil;
    self.duration = 0;
    self.sleepMinutesRemaining = 0;
    [self.sleepTimer invalidate];
    self.sleepTimer = nil;
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    [self notify];
}

- (void)persistProgress {
    if (self.currentBookID && self.duration > 0) {
        double fraction = MAX(0, MIN(1, self.currentTime / self.duration));
        [[ORLibrary shared] setProgress:fraction forBookID:self.currentBookID];
        [[ORLibrary shared] save];
    }
}

- (void)setRate:(float)rate {
    _rate = MAX(0.5, MIN(3.0, rate));
    if (self.player) {
        BOOL playing = self.isPlaying;
        [self.player play];
        self.player.rate = _rate;
        if (!playing) [self.player pause];
    }
    [ORSettings shared].playbackRate = _rate;
    [self updateNowPlaying];
}

#pragma mark - Sleep timer

- (void)startSleepTimerWithMinutes:(NSInteger)minutes {
    [self.sleepTimer invalidate];
    self.sleepMinutesRemaining = MAX(1, minutes);
    self.sleepTimer = [NSTimer scheduledTimerWithTimeInterval:30
                                                      repeats:YES
                                                        block:^(NSTimer *timer) {
        [self updateSleepCountdown];
    }];
    [self notify];
}

- (void)cancelSleepTimer {
    [self.sleepTimer invalidate];
    self.sleepTimer = nil;
    self.sleepMinutesRemaining = 0;
    [self notify];
}

- (void)updateSleepCountdown {
    if (self.sleepMinutesRemaining <= 0) {
        [self.sleepTimer invalidate];
        self.sleepTimer = nil;
        return;
    }
    static NSUInteger tick = 0;
    tick++;
    if (tick % 2 == 0) {
        self.sleepMinutesRemaining -= 1;
    }
    if (self.sleepMinutesRemaining <= 0) {
        [self pause];
        [self.sleepTimer invalidate];
        self.sleepTimer = nil;
        [self notify];
    } else {
        [self notify];
    }
}

#pragma mark - Now playing

- (void)configureRemoteCommands {
    MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
    [center.playCommand addTarget:self action:@selector(remotePlay:)];
    [center.pauseCommand addTarget:self action:@selector(remotePause:)];
    [center.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle:)];
    [center.skipForwardCommand addTarget:self action:@selector(remoteForward:)];
    [center.skipBackwardCommand addTarget:self action:@selector(remoteBackward:)];
    [center.changePlaybackPositionCommand addTarget:self action:@selector(remoteChangePosition:)];
}

- (void)remotePlay:(MPRemoteCommandEvent *)event { [self play]; }
- (void)remotePause:(MPRemoteCommandEvent *)event { [self pause]; }
- (void)remoteToggle:(MPRemoteCommandEvent *)event { [self toggle]; }
- (void)remoteForward:(MPRemoteCommandEvent *)event { [self skip:30]; }
- (void)remoteBackward:(MPRemoteCommandEvent *)event { [self skip:-30]; }

- (void)remoteChangePosition:(MPChangePlaybackPositionCommandEvent *)event {
    [self seekToTime:event.positionTime];
}

- (void)updateNowPlaying {
    if (!self.title) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.title;
    if (self.author.length > 0) info[MPMediaItemPropertyArtist] = self.author;
    info[MPMediaItemPropertyPlaybackDuration] = @(MAX(0, self.duration));
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(MAX(0, self.currentTime));
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.rate);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)notify {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ORAudioPlayerDidChangeNotification object:self];
    });
}

#pragma mark - Events

- (void)itemDidFinish:(NSNotification *)notification {
    if (self.currentBookID) {
        [[ORLibrary shared] setProgress:1.0 forBookID:self.currentBookID];
        [[ORLibrary shared] save];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    [self notify];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORAudioPlayerDidFinishNotification object:self];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    [self persistProgress];
}

- (void)dealloc {
    if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
    if (self.observedCurrentItem && self.player.currentItem) {
        @try {
            [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
        }
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
