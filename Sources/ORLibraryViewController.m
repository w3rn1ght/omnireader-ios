#import "ORLibraryViewController.h"
#import "ORAudioPlayer.h"
#import "ORAudioPlayerController.h"
#import "ORBookImporter.h"
#import "ORCore.h"
#import "ORMetadata.h"
#import "OROPDS.h"
#import "OROPDSViewController.h"
#import "ORReaderFactory.h"
#import "ORReaderSettingsController.h"
#import "ORSettingsViewController.h"
#import "ORUtil.h"
#import "ORYandexViewController.h"

static NSString *const ORLibrarySortKey = @"or.librarySort";

#pragma mark - Book cell

@interface ORBookCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation ORBookCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor clearColor];

        self.coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.clipsToBounds = YES;
        self.coverView.layer.cornerRadius = 6;
        self.coverView.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1.0];
        self.coverView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.coverView.layer.shadowOpacity = 0.18;
        self.coverView.layer.shadowRadius = 6;
        self.coverView.layer.shadowOffset = CGSizeMake(0, 3);
        [self.contentView addSubview:self.coverView];

        self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.placeholderLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        self.placeholderLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        self.placeholderLabel.textAlignment = NSTextAlignmentCenter;
        [self.coverView addSubview:self.placeholderLabel];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.titleLabel];

        self.authorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.authorLabel.font = [UIFont systemFontOfSize:11];
        self.authorLabel.textColor = [UIColor grayColor];
        self.authorLabel.numberOfLines = 1;
        [self.contentView addSubview:self.authorLabel];

        self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.badgeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        self.badgeLabel.textColor = [UIColor whiteColor];
        self.badgeLabel.textAlignment = NSTextAlignmentCenter;
        self.badgeLabel.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.82];
        self.badgeLabel.layer.cornerRadius = 4;
        self.badgeLabel.clipsToBounds = YES;
        [self.coverView addSubview:self.badgeLabel];

        self.progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
        self.progressTrack.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        self.progressTrack.layer.cornerRadius = 1.5;
        [self.contentView addSubview:self.progressTrack];

        self.progressFill = [[UIView alloc] initWithFrame:CGRectZero];
        self.progressFill.backgroundColor = [UIColor colorWithRed:0.86 green:0.42 blue:0.22 alpha:1.0];
        self.progressFill.layer.cornerRadius = 1.5;
        [self.progressTrack addSubview:self.progressFill];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat coverHeight = width * 1.42;
    self.coverView.frame = CGRectMake(0, 0, width, coverHeight);
    self.placeholderLabel.frame = self.coverView.bounds;
    self.badgeLabel.frame = CGRectMake(width - 40, 6, 34, 15);
    self.progressTrack.frame = CGRectMake(0, coverHeight + 7, width, 3);
    CGFloat progress = self.progressFill.tag;
    (void)progress;
    self.titleLabel.frame = CGRectMake(0, coverHeight + 16, width, 32);
    self.authorLabel.frame = CGRectMake(0, coverHeight + 49, width, 15);
}

- (void)configureWithBook:(ORBook *)book {
    self.titleLabel.text = book.title;
    self.authorLabel.text = book.displayAuthor;
    self.badgeLabel.text = book.formatLabel;
    self.badgeLabel.hidden = (book.format == ORBookFormatUnknown);

    UIImage *cover = [ORMetadata coverImageForBook:book];
    self.coverView.image = cover;
    if (cover) {
        self.placeholderLabel.hidden = YES;
        self.coverView.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1.0];
    } else {
        self.placeholderLabel.hidden = NO;
        self.coverView.backgroundColor = [self colorForBook:book];
        NSString *initials = [self initialsForTitle:book.title];
        self.placeholderLabel.text = initials;
    }

    CGFloat width = self.contentView.bounds.size.width;
    self.progressTrack.hidden = book.progress <= 0.001;
    CGFloat fraction = MAX(0.0, MIN(1.0, book.progress));
    self.progressFill.frame = CGRectMake(0, 0, width * fraction, 3);
}

- (UIColor *)colorForBook:(ORBook *)book {
    NSUInteger hash = book.bookID.hash;
    CGFloat hue = (CGFloat)(hash % 360) / 360.0;
    return [UIColor colorWithHue:hue saturation:0.42 brightness:0.62 alpha:1.0];
}

- (NSString *)initialsForTitle:(NSString *)title {
    NSArray<NSString *> *words = [title componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableString *result = [NSMutableString string];
    for (NSString *word in words) {
        if (word.length == 0) continue;
        [result appendString:[word substringToIndex:1].uppercaseString];
        if (result.length >= 2) break;
    }
    return result.length > 0 ? result : @"?";
}

@end

#pragma mark - Mini player

@interface ORMiniPlayerView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation ORMiniPlayerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.97];
        self.layer.cornerRadius = 10;
        self.hidden = YES;

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.titleLabel];

        self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.playButton.tintColor = [UIColor whiteColor];
        self.playButton.titleLabel.font = [UIFont systemFontOfSize:20];
        [self addSubview:self.playButton];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(14, 0, self.bounds.size.width - 66, self.bounds.size.height);
    self.playButton.frame = CGRectMake(self.bounds.size.width - 52, 0, 44, self.bounds.size.height);
}

- (void)handleTap {
    if (self.onTap) self.onTap();
}

@end

#pragma mark - Library

@interface ORLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<ORBook *> *visibleBooks;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) NSInteger filterIndex;
@property (nonatomic) NSInteger sortIndex;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) ORMiniPlayerView *miniPlayer;
@property (nonatomic, strong) UIActivityIndicatorView *importSpinner;
@end

@implementation ORLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ORPaths supportDirectory];
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.title = @"Библиотека";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.searchText = @"";
    self.filterIndex = 0;
    self.sortIndex = [[NSUserDefaults standardUserDefaults] integerForKey:ORLibrarySortKey];
    self.visibleBooks = [NSMutableArray array];

    [self buildNavigation];
    [self buildCollectionView];
    [self buildMiniPlayer];
    [self reloadBooks];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(libraryChanged)
                                                 name:ORLibraryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioChanged)
                                                 name:ORAudioPlayerDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self reloadBooks];
    [self audioChanged];
}

- (void)buildNavigation {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self
                                                                        action:@selector(showAddMenu)];
    UIBarButtonItem *sort = [[UIBarButtonItem alloc] initWithTitle:@"⇅"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(showSortMenu)];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithTitle:@"⚙︎"
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(showSettings)];
    self.navigationItem.rightBarButtonItems = @[add, sort];
    self.navigationItem.leftBarButtonItem = settings;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Поиск по названию и автору";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)buildCollectionView {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"Все", @"Книги", @"Документы", @"Аудио"]];
    self.filterControl.selectedSegmentIndex = 0;
    [self.filterControl addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterControl];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 22;
    layout.sectionInset = UIEdgeInsetsMake(10, 14, 24, 14);
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 64, 0);
    [self.collectionView registerClass:[ORBookCell class] forCellWithReuseIdentifier:@"BookCell"];
    [self.view addSubview:self.collectionView];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                            action:@selector(handleLongPress:)];
    [self.collectionView addGestureRecognizer:longPress];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.text = @"Здесь пока пусто.\nНажмите +, чтобы добавить книгу.";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.color = [UIColor darkGrayColor];
    spinner.hidesWhenStopped = YES;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:spinner];
    self.importSpinner = spinner;

    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.filterControl.heightAnchor constraintEqualToConstant:32],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:4],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8],

        [self.importSpinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.importSpinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)buildMiniPlayer {
    self.miniPlayer = [[ORMiniPlayerView alloc] initWithFrame:CGRectZero];
    self.miniPlayer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.miniPlayer];
    __weak typeof(self) weakSelf = self;
    self.miniPlayer.onTap = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *bookID = [ORAudioPlayer shared].currentBookID;
        ORBook *book = bookID ? [[ORLibrary shared] bookWithID:bookID] : nil;
        if (book) {
            [strongSelf openBook:book];
            return;
        }
        if ([ORAudioPlayer shared].hasTrack) {
            ORAudioPlayerController *player = [[ORAudioPlayerController alloc]
                initWithBook:book
                   localPath:nil];
            [strongSelf.navigationController pushViewController:player animated:YES];
        }
    };
    [self.miniPlayer.playButton addTarget:self action:@selector(toggleMiniPlayer) forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [self.miniPlayer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.miniPlayer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.miniPlayer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [self.miniPlayer.heightAnchor constraintEqualToConstant:52]
    ]];
}

#pragma mark - Data

- (void)libraryChanged {
    [self reloadBooks];
}

- (void)reloadBooks {
    NSArray<ORBook *> *all = [ORLibrary shared].books;
    NSMutableArray *filtered = [NSMutableArray array];
    NSString *query = self.searchText.lowercaseString;

    for (ORBook *book in all) {
        if (self.filterIndex == 1) {
            if (book.isAudio || book.isOffice) continue;
            if (book.format == ORBookFormatPDF) {
                // PDFs are documents, but readers expect them in "Книги" too; keep here.
            }
        } else if (self.filterIndex == 2) {
            if (!book.isOffice && book.format != ORBookFormatPDF) continue;
        } else if (self.filterIndex == 3) {
            if (!book.isAudio) continue;
        }
        if (query.length > 0) {
            BOOL matches = [book.title.lowercaseString containsString:query] ||
                           [book.author.lowercaseString containsString:query];
            if (!matches) continue;
        }
        [filtered addObject:book];
    }

    [filtered sortUsingComparator:^NSComparisonResult(ORBook *a, ORBook *b) {
        switch (self.sortIndex) {
            case 1: return [a.title localizedCaseInsensitiveCompare:b.title];
            case 2: return [a.author localizedCaseInsensitiveCompare:b.author];
            case 3: {
                NSDate *left = a.lastOpenedAt ?: a.addedAt;
                NSDate *right = b.lastOpenedAt ?: b.addedAt;
                return [right compare:left];
            }
            default: return [b.addedAt compare:a.addedAt];
        }
    }];

    [self.visibleBooks setArray:filtered];
    [self.collectionView reloadData];
    self.emptyLabel.hidden = self.visibleBooks.count > 0;
}

- (void)filterChanged {
    self.filterIndex = self.filterControl.selectedSegmentIndex;
    [self reloadBooks];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text ?: @"";
    [self reloadBooks];
}

#pragma mark - Collection view

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.visibleBooks.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ORBookCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"BookCell" forIndexPath:indexPath];
    ORBook *book = self.visibleBooks[(NSUInteger)indexPath.item];
    [cell configureWithBook:book];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = collectionView.bounds.size.width;
    BOOL iPad = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
    NSInteger columns = iPad ? (width > 900 ? 6 : 4) : 3;
    CGFloat spacing = 12 * (columns - 1) + 28;
    CGFloat itemWidth = floor((width - spacing) / columns);
    return CGSizeMake(itemWidth, itemWidth * 1.42 + 70);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    ORBook *book = self.visibleBooks[(NSUInteger)indexPath.item];
    [self openBook:book];
}

- (void)openBook:(ORBook *)book {
    __weak typeof(self) weakSelf = self;
    [self setImporting:YES message:nil];
    [ORReaderFactory openBook:book presenter:self completion:^(UIViewController *controller, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf setImporting:NO message:nil];
        if (!strongSelf) return;
        if (!controller) {
            [ORUtil presentAlertIn:strongSelf
                             title:@"Не удалось открыть"
                           message:error.localizedDescription ?: @"Формат не поддерживается."];
            return;
        }
        [strongSelf.navigationController pushViewController:controller animated:YES];
    }];
}

- (void)setImporting:(BOOL)importing message:(NSString *)message {
    if (importing) {
        [self.importSpinner startAnimating];
        self.view.userInteractionEnabled = NO;
        self.importSpinner.userInteractionEnabled = NO;
    } else {
        [self.importSpinner stopAnimating];
        self.view.userInteractionEnabled = YES;
    }
}

#pragma mark - Context menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath) return;
    ORBook *book = self.visibleBooks[(NSUInteger)indexPath.item];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:book.title
                                                                  message:book.displayAuthor
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Открыть" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openBook:book];
    }]];
    if (!book.isAudio && book.audioURL.length == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Поделиться файлом" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *path = [ORPaths pathForBook:book];
            if (path.length == 0) return;
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                                                                applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
            [self presentViewController:share animated:YES completion:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Удалить" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Удалить книгу?"
                                                                        message:@"Файл будет удалён из библиотеки."
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Удалить" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action2) {
            [[ORLibrary shared] removeBook:book deleteFiles:YES];
        }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:confirm animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.collectionView;
    sheet.popoverPresentationController.sourceRect = CGRectMake(point.x, point.y, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Add menu

- (void)showAddMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Импортировать файл" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentDocumentPicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Яндекс Книги" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ORYandexViewController *yandex = [[ORYandexViewController alloc] init];
        [self.navigationController pushViewController:yandex animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Каталог OPDS" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [OROPDSViewController presentPickerFrom:self];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Аудио по ссылке" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForRemoteAudio];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentDocumentPicker {
    NSArray<NSString *> *types = @[
        @"com.adobe.pdf", @"org.idpf.epub-container", @"com.omnireader.fb2",
        @"public.plain-text", @"public.html", @"net.daringfireball.markdown",
        @"com.microsoft.word.doc", @"org.openxmlformats.wordprocessingml.document",
        @"com.microsoft.excel.xls", @"org.openxmlformats.spreadsheetml.sheet",
        @"com.microsoft.powerpoint.ppt", @"org.openxmlformats.presentationml.presentation",
        @"public.zip-archive", @"com.omnireader.cbz", @"com.omnireader.cbr",
        @"com.amazon.mobi", @"com.amazon.azw3", @"com.omnireader.djvu",
        @"public.audio", @"public.mp3", @"public.mpeg-4-audio", @"public.data"
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types
                                                                                                   inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self importURLs:urls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

- (void)importURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    [self setImporting:YES message:nil];
    __block NSInteger remaining = (NSInteger)urls.count;
    __block NSError *lastError = nil;
    for (NSURL *url in urls) {
        [[ORBookImporter shared] importFileAtURL:url completion:^(ORBook *book, NSError *error) {
            if (error) lastError = error;
            remaining -= 1;
            if (remaining > 0) return;
            [self setImporting:NO message:nil];
            [self reloadBooks];
            if (lastError) {
                [ORUtil presentAlertIn:self title:@"Импорт" message:lastError.localizedDescription];
            }
        }];
    }
}

- (void)promptForRemoteAudio {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Аудио по ссылке"
                                                                  message:@"Вставьте прямую ссылку на MP3/M4B или поток."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Название";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Автор (необязательно)";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://…/book.m4b";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Добавить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = alert.textFields[0].text;
        NSString *author = alert.textFields[1].text;
        NSString *url = alert.textFields[2].text;
        if (url.length < 8) return;
        [[ORBookImporter shared] addRemoteAudioWithTitle:title author:author url:url];
        [self reloadBooks];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Sorting

- (void)showSortMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Сортировка"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"Сначала новые", @"По названию", @"По автору", @"Недавно открытые"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.sortIndex = (NSInteger)i;
            [[NSUserDefaults standardUserDefaults] setInteger:self.sortIndex forKey:ORLibrarySortKey];
            [self reloadBooks];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showSettings {
    ORSettingsViewController *settings = [[ORSettingsViewController alloc] init];
    [self.navigationController pushViewController:settings animated:YES];
}

#pragma mark - Mini player

- (void)audioChanged {
    ORAudioPlayer *player = [ORAudioPlayer shared];
    BOOL visible = player.hasTrack;
    self.miniPlayer.hidden = !visible;
    if (visible) {
        self.miniPlayer.titleLabel.text = player.title;
        [self.miniPlayer.playButton setTitle:player.isPlaying ? @"⏸" : @"▶" forState:UIControlStateNormal];
        self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 76, 0);
    } else {
        self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    }
}

- (void)toggleMiniPlayer {
    [[ORAudioPlayer shared] toggle];
}

#pragma mark - Incoming files

- (void)handleIncomingFileURL:(NSURL *)url {
    [self importURLs:@[url]];
}

@end