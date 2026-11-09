#import "ORAudioPlayerController.h"
#import "ORAudioPlayer.h"
#import "ORMetadata.h"
#import "ORUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface ORAudioPlayerController ()
@property (nonatomic, strong) ORBook *book;
@property (nonatomic, copy, nullable) NSString *localPath;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *speedButton;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL scrubbing;
@end

@implementation ORAudioPlayerController

- (instancetype)initWithBook:(ORBook *)book localPath:(NSString *)localPath {
    self = [super init];
    if (self) {
        _book = book;
        _localPath = [localPath copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.10 blue:0.12 alpha:1.0];
    [self buildInterface];
    [self observe];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    self.navigationItem.title = @"Аудиокнига";
    [self startIfNeeded];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Do not deactivate the audio session: playback must continue in background.
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observe {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh)
                                                 name:ORAudioPlayerDidChangeNotification
                                               object:nil];
}

- (NSURL *)mediaURL {
    if (self.localPath.length > 0) return [NSURL fileURLWithPath:self.localPath];
    if (self.book.audioURL.length > 0) return [NSURL URLWithString:self.book.audioURL];
    NSString *path = [ORPaths pathForBook:self.book];
    if (path.length > 0) return [NSURL fileURLWithPath:path];
    return nil;
}

- (void)startIfNeeded {
    if (self.started) return;
    self.started = YES;
    ORAudioPlayer *player = [ORAudioPlayer shared];
    if ([player.currentBookID isEqualToString:self.book.bookID] && player.hasTrack) {
        return;
    }
    NSURL *url = [self mediaURL];
    if (!url) {
        [ORUtil presentAlertIn:self title:@"Аудио" message:@"Не найден файл для воспроизведения."];
        return;
    }
    [player playURL:url title:self.book.title author:self.book.author bookID:self.book.bookID headers:nil];
}

- (void)buildInterface {
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = 40;

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectMake((width - 220) / 2, top, 220, 220)];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 14;
    self.artworkView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    UIImage *cover = [ORMetadata coverImageForBook:self.book];
    self.artworkView.image = cover ?: [self placeholderArtwork];
    [self.view addSubview:self.artworkView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, top + 242, width - 48, 52)];
    self.titleLabel.text = self.book.title;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    [self.view addSubview:self.titleLabel];

    self.authorLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, top + 296, width - 48, 22)];
    self.authorLabel.text = self.book.displayAuthor;
    self.authorLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    self.authorLabel.font = [UIFont systemFontOfSize:14];
    self.authorLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.authorLabel];

    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(24, top + 340, width - 48, 30)];
    self.progressSlider.minimumValue = 0;
    self.progressSlider.maximumValue = 1;
    self.progressSlider.tintColor = [UIColor colorWithRed:0.95 green:0.62 blue:0.28 alpha:1.0];
    [self.progressSlider addTarget:self action:@selector(beginScrub) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(endScrub) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.progressSlider];

    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, top + 372, width - 48, 18)];
    self.timeLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.text = @"0:00 · 0:00";
    [self.view addSubview:self.timeLabel];

    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playButton.frame = CGRectMake((width - 76) / 2, top + 410, 76, 76);
    self.playButton.tintColor = [UIColor whiteColor];
    [self.playButton setTitle:@"▶" forState:UIControlStateNormal];
    self.playButton.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightRegular];
    self.playButton.layer.cornerRadius = 38;
    self.playButton.layer.borderWidth = 2;
    self.playButton.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
    [self.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playButton];

    UIButton *back30 = [UIButton buttonWithType:UIButtonTypeSystem];
    back30.frame = CGRectMake(width / 2 - 140, top + 426, 56, 44);
    [back30 setTitle:@"−30" forState:UIControlStateNormal];
    [back30 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [back30 addTarget:self action:@selector(seekBackward) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back30];

    UIButton *forward30 = [UIButton buttonWithType:UIButtonTypeSystem];
    forward30.frame = CGRectMake(width / 2 + 84, top + 426, 56, 44);
    [forward30 setTitle:@"+30" forState:UIControlStateNormal];
    [forward30 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [forward30 addTarget:self action:@selector(seekForward) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:forward30];

    CGFloat controlsY = top + 500;
    self.speedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.speedButton.frame = CGRectMake(20, controlsY, 110, 40);
    [self.speedButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.speedButton addTarget:self action:@selector(cycleSpeed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.speedButton];

    self.sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sleepButton.frame = CGRectMake(width - 130, controlsY, 110, 40);
    [self.sleepButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.sleepButton addTarget:self action:@selector(configureSleepTimer) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sleepButton];
}

- (UIImage *)placeholderArtwork {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(220, 220), YES, 0);
    [[UIColor colorWithWhite:0.2 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, 220, 220));
    [[UIColor colorWithWhite:0.45 alpha:1] setFill];
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(85, 60, 50, 50)];
    [path fill];
    [[UIColor colorWithWhite:0.45 alpha:1] setFill];
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(70, 118, 80, 60) cornerRadius:20];
    [body fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - State

- (void)refresh {
    ORAudioPlayer *player = [ORAudioPlayer shared];
    BOOL playing = player.isPlaying;
    [self.playButton setTitle:playing ? @"⏸" : @"▶" forState:UIControlStateNormal];
    [self.speedButton setTitle:[NSString stringWithFormat:@"×%.2g", player.rate] forState:UIControlStateNormal];
    if (player.sleepMinutesRemaining > 0) {
        [self.sleepButton setTitle:[NSString stringWithFormat:@"⏱ %ld мин", (long)player.sleepMinutesRemaining]
                          forState:UIControlStateNormal];
    } else {
        [self.sleepButton setTitle:@"⏱ Таймер" forState:UIControlStateNormal];
    }
    if (!self.scrubbing) {
        double current = player.currentTime;
        double duration = player.duration;
        if (duration > 0) {
            self.progressSlider.value = (float)MIN(1.0, current / duration);
        }
        self.timeLabel.text = [NSString stringWithFormat:@"%@ · %@",
                               [self formatTime:current], [self formatTime:duration]];
    }
}

- (NSString *)formatTime:(double)seconds {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger total = (NSInteger)llround(seconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)secs];
}

- (void)togglePlay {
    [[ORAudioPlayer shared] toggle];
    [self refresh];
}

- (void)beginScrub { self.scrubbing = YES; }

- (void)endScrub {
    self.scrubbing = NO;
    ORAudioPlayer *player = [ORAudioPlayer shared];
    [player seekToTime:self.progressSlider.value * player.duration];
    [self refresh];
}

- (void)seekForward { [[ORAudioPlayer shared] skip:30]; [self refresh]; }
- (void)seekBackward { [[ORAudioPlayer shared] skip:-30]; [self refresh]; }

- (void)cycleSpeed {
    NSArray<NSNumber *> *rates = @[@0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    ORAudioPlayer *player = [ORAudioPlayer shared];
    float current = player.rate;
    NSUInteger next = 1;
    for (NSUInteger i = 0; i < rates.count; i++) {
        if (fabs(rates[i].floatValue - current) < 0.01) {
            next = (i + 1) % rates.count;
            break;
        }
    }
    player.rate = rates[next].floatValue;
    [ORSettings shared].playbackRate = player.rate;
    [self refresh];
}

- (void)configureSleepTimer {
    ORAudioPlayer *player = [ORAudioPlayer shared];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Таймер сна"
                                                                  message:@"Остановить воспроизведение через:"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *minutes in @[@5, @15, @30, @45, @60]) {
        NSString *title = [NSString stringWithFormat:@"%@ мин", minutes];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [player startSleepTimerWithMinutes:minutes.integerValue];
            [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Выключить таймер" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [player cancelSleepTimer];
        [self refresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.sleepButton;
    sheet.popoverPresentationController.sourceRect = self.sleepButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end