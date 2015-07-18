#import "ViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "SLTImgViewerVC.h"


@interface ViewController () <SLTImgViewerVCDismissDelegate>
@property (nonatomic, strong) SLTImgViewerVC *imageViewerVC;
@end


@implementation ViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	UIButton *showButton = [UIButton buttonWithType:UIButtonTypeCustom];
	showButton.layer.cornerRadius = 5;
	showButton.layer.borderWidth = 1.f / [UIScreen mainScreen].scale;
	showButton.layer.borderColor = [UIColor blueColor].CGColor;
	[showButton setTitle:@"show" forState:UIControlStateNormal];
	[showButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
	[showButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateHighlighted];
	showButton.titleLabel.textAlignment = NSTextAlignmentCenter;
	showButton.titleLabel.font = [UIFont systemFontOfSize:14];
	showButton.frame = (CGRect) {
		.origin.x = (self.view.bounds.size.width - 150.f) * 0.5f,
		.origin.y = (self.view.bounds.size.height - 40.f) * 0.5f,
		.size.width = 150.f,
		.size.height = 40.f
	};
	showButton.autoresizingMask =
		UIViewAutoresizingFlexibleLeftMargin |
		UIViewAutoresizingFlexibleRightMargin |
		UIViewAutoresizingFlexibleTopMargin |
		UIViewAutoresizingFlexibleBottomMargin;
	[showButton addTarget:self action:@selector(didTapShowButton) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:showButton];
}

- (void)didTapShowButton
{
	[self showImageViewer];
}

- (void)imageViewerDidDismiss:(SLTImgViewerVC *)imageViewerVC
{
	[self hideImageViewer];
}

- (void)showImageViewer
{
	if (self.imageViewerVC)
		return;

	UIImage *img = [UIImage imageNamed:@"lena.png"];

	self.imageViewerVC = [[SLTImgViewerVC alloc] initWithImage:img];
	self.imageViewerVC.dismissDelegate = self;

	[self addChildViewController:self.imageViewerVC];
	self.imageViewerVC.view.frame = self.view.bounds;
	self.imageViewerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.imageViewerVC.view];
	[self.imageViewerVC didMoveToParentViewController:self];
}

- (void)hideImageViewer
{
	if (!self.imageViewerVC)
		return;

	[self.imageViewerVC willMoveToParentViewController:nil];
	[self.imageViewerVC.view removeFromSuperview];
	[self.imageViewerVC removeFromParentViewController];

	self.imageViewerVC = nil;
}

@end
