// SweetTune: GPU clock / thermal limit / reboot controls for the SWEET (OnePlus 3T) iOS port.
// Talks to the kernel through sysctls (bsd/dev/sweet_gpu.c): kern.sweet_gpu_max, kern.sweet_gpu_cur, kern.sweet_temp (0.1 C),
// kern.sweet_tlimit, kern.sweet_reboot ("fastboot" / "recovery" / "system").
#import <UIKit/UIKit.h>
#include <sys/sysctl.h>

static int rd(const char *name) {
    int v = -1;
    size_t n = sizeof(v);
    if (sysctlbyname(name, &v, &n, NULL, 0) != 0) return -1;
    return v;
}

static BOOL wr(const char *name, int v) {
    return sysctlbyname(name, NULL, NULL, &v, sizeof(v)) == 0;
}

static BOOL reboot_to(const char *what) {
    return sysctlbyname("kern.sweet_reboot", NULL, NULL, (void *)what, strlen(what) + 1) == 0;
}

@interface TuneVC : UIViewController
@property (strong) UILabel *status;
@property (strong) UISegmentedControl *clk;
@property (strong) UISlider *limit;
@property (strong) UILabel *limitLabel;
@property (strong) NSTimer *timer;
@end

@implementation TuneVC

- (UILabel *)label:(NSString *)t y:(CGFloat)y size:(CGFloat)sz {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, sz * 1.5)];
    l.text = t;
    l.font = [UIFont systemFontOfSize:sz];
    l.numberOfLines = 0;
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:l];
    return l;
}

- (UIButton *)button:(NSString *)t y:(CGFloat)y action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(16, y, self.view.bounds.size.width - 32, 44);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:t forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    CGFloat y = 56;
    [self label:@"SweetTune" y:y size:28]; y += 48;
    self.status = [self label:@"..." y:y size:17]; self.status.numberOfLines = 3; y += 80;

    [self label:@"GPU top clock (MHz)" y:y size:15]; y += 28;
    self.clk = [[UISegmentedControl alloc] initWithItems:@[@"200", @"300", @"400", @"600"]];
    self.clk.frame = CGRectMake(16, y, self.view.bounds.size.width - 32, 36);
    self.clk.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.clk addTarget:self action:@selector(clkChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.clk]; y += 56;

    self.limitLabel = [self label:@"" y:y size:15]; y += 28;
    self.limit = [[UISlider alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, 30)];
    self.limit.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.limit.minimumValue = 50;
    self.limit.maximumValue = 95;
    [self.limit addTarget:self action:@selector(limitChanged) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.limit addTarget:self action:@selector(limitDragging) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.limit]; y += 52;

    [self label:@"Resolution and scale are fixed at boot (boot image); they cannot be changed from here." y:y size:13]; y += 52;

    [self button:@"Reboot to TWRP (recovery)" y:y action:@selector(toRecovery)]; y += 54;
    [self button:@"Reboot to fastboot (bootloader)" y:y action:@selector(toFastboot)]; y += 54;
    [self button:@"Reboot (back into the bootloader menu path)" y:y action:@selector(toSystem)]; y += 54;

    int max = rd("kern.sweet_gpu_max"), lim = rd("kern.sweet_tlimit");
    int idx = max == 200 ? 0 : max == 300 ? 1 : max == 400 ? 2 : 3;
    self.clk.selectedSegmentIndex = idx;
    if (lim > 0) self.limit.value = lim;
    [self limitDragging];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}

- (void)tick {
    int t = rd("kern.sweet_temp"), cur = rd("kern.sweet_gpu_cur");
    if (t < 0 && cur < 0) {
        self.status.text = @"kernel controls not found (kern.sweet_*): wrong kernel image?";
        return;
    }
    self.status.text = [NSString stringWithFormat:@"Hottest sensor: %d.%d C\nGPU now: %d MHz", t / 10, t % 10, cur];
}

- (void)clkChanged {
    static const int v[4] = {200, 300, 400, 600};
    int mhz = v[self.clk.selectedSegmentIndex];
    if (!wr("kern.sweet_gpu_max", mhz)) {
        [self alert:@"GPU top clock" msg:[NSString stringWithFormat:@"%d MHz was refused (above the boot clock, or no access).", mhz]];
    }
}

- (void)limitDragging {
    self.limitLabel.text = [NSString stringWithFormat:@"Throttle from %d C (then +7 C, +13 C)", (int)self.limit.value];
}

- (void)limitChanged {
    if (!wr("kern.sweet_tlimit", (int)self.limit.value)) [self alert:@"Thermal limit" msg:@"The kernel refused the value."];
}

- (void)alert:(NSString *)title msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirm:(NSString *)title what:(const char *)what {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:@"The phone restarts immediately. Unsaved work is lost." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reboot" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        if (!reboot_to(what)) [self alert:@"Reboot" msg:@"The kernel refused (sysctl kern.sweet_reboot)."];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toRecovery { [self confirm:@"Reboot to TWRP?" what:"recovery"]; }
- (void)toFastboot { [self confirm:@"Reboot to fastboot?" what:"fastboot"]; }
- (void)toSystem { [self confirm:@"Restart the phone?" what:"system"]; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)o {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [TuneVC new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
