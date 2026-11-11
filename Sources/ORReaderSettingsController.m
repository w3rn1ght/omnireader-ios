#import "ORReaderSettingsController.h"

@implementation ORReaderSettingsController {
    ORSettings *_settings;
    UISegmentedControl *_themeControl;
    UISegmentedControl *_fontControl;
    UISegmentedControl *_directionControl;
    UISlider *_sizeSlider;
    UISlider *_lineHeightSlider;
    UISlider *_marginSlider;
    UISwitch *_justifySwitch;
    UISwitch *_hyphenateSwitch;
    UISwitch *_animateSwitch;
    UISwitch *_simpleLayoutSwitch;
}

- (instancetype)initWithSettings:(ORSettings *)settings {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _settings = settings ?: [ORSettings shared];
        self.title = @"Оформление";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(done)];
    [self buildControls];
    [self reloadUI];
}

- (void)buildControls {
    _themeControl = [[UISegmentedControl alloc] initWithItems:@[@"Бумага", @"Сепия", @"Серый", @"Ночь"]];
    [_themeControl addTarget:self action:@selector(controlChanged) forControlEvents:UIControlEventValueChanged];

    _fontControl = [[UISegmentedControl alloc] initWithItems:@[@"С засечками", @"Без засечек", @"Моно"]];
    [_fontControl addTarget:self action:@selector(controlChanged) forControlEvents:UIControlEventValueChanged];

    _directionControl = [[UISegmentedControl alloc] initWithItems:@[@"Вбок", @"Вниз"]];
    [_directionControl addTarget:self action:@selector(controlChanged) forControlEvents:UIControlEventValueChanged];

    _sizeSlider = [self sliderWithMin:14 max:30 step:1 action:@selector(controlChanged)];
    _lineHeightSlider = [self sliderWithMin:1.1 max:2.0 step:0.05 action:@selector(controlChanged)];
    _marginSlider = [self sliderWithMin:10 max:40 step:1 action:@selector(controlChanged)];

    _justifySwitch = [self switchWithAction:@selector(controlChanged)];
    _hyphenateSwitch = [self switchWithAction:@selector(controlChanged)];
    _animateSwitch = [self switchWithAction:@selector(controlChanged)];
    _simpleLayoutSwitch = [self switchWithAction:@selector(controlChanged)];
}

- (UISlider *)sliderWithMin:(float)min max:(float)max step:(float)step action:(SEL)action {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
}

- (UISwitch *)switchWithAction:(SEL)action {
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (void)reloadUI {
    _themeControl.selectedSegmentIndex = _settings.theme;
    _fontControl.selectedSegmentIndex = _settings.font;
    _directionControl.selectedSegmentIndex = _settings.pageDirection;
    _sizeSlider.value = _settings.fontSize;
    _lineHeightSlider.value = _settings.lineHeight;
    _marginSlider.value = _settings.margin;
    _justifySwitch.on = _settings.justify;
    _hyphenateSwitch.on = _settings.hyphenate;
    _animateSwitch.on = _settings.animatePages;
    _simpleLayoutSwitch.on = _settings.simpleLayout;
}

- (void)controlChanged {
    _settings.theme = _themeControl.selectedSegmentIndex;
    _settings.font = _fontControl.selectedSegmentIndex;
    _settings.pageDirection = _directionControl.selectedSegmentIndex;
    _settings.fontSize = lroundf(_sizeSlider.value);
    _settings.lineHeight = _lineHeightSlider.value;
    _settings.margin = lroundf(_marginSlider.value);
    _settings.justify = _justifySwitch.on;
    _settings.hyphenate = _hyphenateSwitch.on;
    _settings.animatePages = _animateSwitch.on;
    _settings.simpleLayout = _simpleLayoutSwitch.on;
    [_settings synchronize];
    if (self.onChange) self.onChange();
}

- (void)done {
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return 2;
        case 2: return 4;
        default: return 4;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Тема";
        case 1: return @"Шрифт";
        case 2: return @"Текст";
        default: return @"Дополнительно";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = nil;
    }
    cell.textLabel.text = nil;
    cell.accessoryView = nil;
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Тема оформления";
        cell.accessoryView = _themeControl;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Гарнитура";
            cell.accessoryView = _fontControl;
        } else {
            cell.textLabel.text = @"Размер";
            cell.accessoryView = _sizeSlider;
            [self addValueLabel:cell forValue:[NSString stringWithFormat:@"%ld pt", (long)_settings.fontSize]];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Межстрочный";
            cell.accessoryView = _lineHeightSlider;
            [self addValueLabel:cell forValue:[NSString stringWithFormat:@"%.2f", _settings.lineHeight]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Отступы";
            cell.accessoryView = _marginSlider;
            [self addValueLabel:cell forValue:[NSString stringWithFormat:@"%ld px", (long)_settings.margin]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Выравнивание";
            cell.accessoryView = _justifySwitch;
        } else {
            cell.textLabel.text = @"Перелистывание";
            cell.accessoryView = _directionControl;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Переносы";
            cell.accessoryView = _hyphenateSwitch;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Анимация страниц";
            cell.accessoryView = _animateSwitch;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Простая вёрстка";
            cell.detailTextLabel.text = @"без CSS книги";
            cell.accessoryView = _simpleLayoutSwitch;
        } else {
            cell.textLabel.text = @"Скорость озвучки";
            cell.accessoryView = nil;
            [self addRateLabelToCell:cell];
        }
    }
    return cell;
}

- (void)addValueLabel:(UITableViewCell *)cell forValue:(NSString *)value {
    cell.detailTextLabel.text = value;
    cell.detailTextLabel.textColor = [UIColor grayColor];
}

- (void)addRateLabelToCell:(UITableViewCell *)cell {
    UISlider *rate = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
    rate.minimumValue = 0.25;
    rate.maximumValue = 0.75;
    rate.value = [ORSettings shared].speechRate;
    [rate addTarget:self action:@selector(rateChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = rate;
}

- (void)rateChanged:(UISlider *)slider {
    [ORSettings shared].speechRate = slider.value;
    [[ORSettings shared] synchronize];
}

@end
