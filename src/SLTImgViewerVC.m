#import "SLTImgViewerVC.h"


static const CGFloat kSLTTargetZoomForDoubleTap = 3.0f;
static const CGFloat kSLTMinScalingForExpandingOffscreenStyleTransition = 0.75f;
static const CGFloat kSLTMaxScalingForExpandingOffscreenStyleTransition = 1.25f;
static const CGFloat kSLTTransitionAnimationDuration = 0.2f;
static const CGFloat kSLTMinimumFlickDismissalVelocity = 800.0f;


@interface SLTImgViewerVC () <UIScrollViewDelegate, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong, readwrite) UIImage *image;
@property (nonatomic, assign) UIInterfaceOrientation lastUsedOrientation;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CGPoint panStartPoint;
@property (nonatomic, assign) CGPoint panStartImageViewCenter;
@property (nonatomic, assign, getter=isAnimatingPresentationOrDismissal) BOOL animatingPresentationOrDismissal;
@property (nonatomic, assign, getter=isPresented) BOOL presented;
@property (nonatomic, assign, getter=isRotationTransformDirty) BOOL rotationTransformDirty;
@property (nonatomic, assign, getter=isImageFlickingAwayForDismissal) BOOL imageFlickingAwayForDismissal;
@property (nonatomic, assign, getter=isDraggingImage) BOOL draggingImage;
@property (nonatomic, assign, getter=isScrollViewAnimatingZoom) BOOL scrollViewAnimatingZoom;
@end


@implementation SLTImgViewerVC

- (instancetype)initWithImage:(UIImage *)img
{
	self = [super initWithNibName:nil bundle:nil];
	if (!self) return nil;

	NSCParameterAssert(img);

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(deviceOrientationDidChange:)
												 name:UIDeviceOrientationDidChangeNotification
											   object:nil];

	_image = [img copy];

	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:UIDeviceOrientationDidChangeNotification
												  object:nil];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
	self.backgroundView.backgroundColor = [UIColor blackColor];
	self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.backgroundView];

	self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	self.scrollView.delegate = self;
	self.scrollView.zoomScale = 1.0f;
	self.scrollView.maximumZoomScale = 8.0f;
	self.scrollView.scrollEnabled = NO;
	self.scrollView.isAccessibilityElement = YES;
	self.scrollView.accessibilityLabel = self.accessibilityLabel;
	[self.view addSubview:self.scrollView];

	self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.imageView.frame = (CGRect) {
		.origin.x = (self.view.bounds.size.width  - self.image.size.width)  * 0.5f,
		.origin.y = (self.view.bounds.size.height - self.image.size.height) * 0.5f,
		.size = self.image.size
	};
	self.imageView.contentMode = UIViewContentModeScaleAspectFill;
	self.imageView.userInteractionEnabled = YES;
	self.imageView.isAccessibilityElement = NO;
	self.imageView.clipsToBounds = YES;
	self.imageView.layer.allowsEdgeAntialiasing = YES;
	[self.scrollView addSubview:self.imageView];

	UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDoubleTapped:)];
	doubleTapRecognizer.numberOfTapsRequired = 2;
	doubleTapRecognizer.delegate = self;
	[self.view addGestureRecognizer:doubleTapRecognizer];

	UITapGestureRecognizer *singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageSingleTapped:)];
	[singleTapRecognizer requireGestureRecognizerToFail:doubleTapRecognizer];
	singleTapRecognizer.delegate = self;
	[self.view addGestureRecognizer:singleTapRecognizer];

	self.panRecognizer = [[UIPanGestureRecognizer alloc] init];
	self.panRecognizer.maximumNumberOfTouches = 1;
	[self.panRecognizer addTarget:self action:@selector(dismissingPanGestureRecognizerPanned:)];
	self.panRecognizer.delegate = self;
	[self.scrollView addGestureRecognizer:self.panRecognizer];

	[self updateInterfaceWithImage:self.image];


	// show animated
	self.animatingPresentationOrDismissal = YES;
	self.view.userInteractionEnabled = NO;
	self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
	self.view.alpha = 0;
	self.scrollView.frame = self.view.bounds;
	[self updateScrollViewAndImageViewForCurrentMetrics];
	self.scrollView.transform = CGAffineTransformMakeScale(kSLTMinScalingForExpandingOffscreenStyleTransition,
														   kSLTMinScalingForExpandingOffscreenStyleTransition);
	[UIView animateWithDuration:kSLTTransitionAnimationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
		self.view.alpha = 1.f;
		self.scrollView.transform = CGAffineTransformIdentity;
	} completion:^(BOOL finished) {
		self.animatingPresentationOrDismissal = NO;
		self.presented = YES;
		self.view.userInteractionEnabled = YES;
	}];
}

- (void)dismissAnimated
{
	if (!self.isPresented)
		return;

	self.presented = NO;

	if (self.isImageFlickingAwayForDismissal)
	{
		[self dismissByCleaningUpAfterFlickOffscreen];
	}
	else
	{
		[self dismissByExpandingToOffscreenPosition];
	}
}

- (NSUInteger)supportedInterfaceOrientations
{
	/*
	 iOS 8 changes the behavior of autorotation when presenting a
	 modal view controller whose supported orientations outnumber
	 the orientations of the presenting view controller.

	 E.g., when a portrait-only iPhone view controller presents
	 JTSImageViewController while the **device** is oriented in
	 landscape, on iOS 8 the modal view controller presents straight
	 into landscape, whereas on iOS 7 the interface orientation
	 of the presenting view controller is preserved.

	 In my judgement the iOS 7 behavior is preferable. It also simplifies
	 the rotation corrections during presentation. - August 31, 2014 JTS.
	*/
	if (self.isViewLoaded)
	{
		switch ([UIApplication sharedApplication].statusBarOrientation)
		{
			case UIInterfaceOrientationLandscapeLeft:  return UIInterfaceOrientationMaskLandscapeLeft;
			case UIInterfaceOrientationLandscapeRight: return UIInterfaceOrientationMaskLandscapeRight;
			case UIInterfaceOrientationPortrait:       return UIInterfaceOrientationMaskPortrait;
			case UIInterfaceOrientationPortraitUpsideDown: return UIInterfaceOrientationMaskPortraitUpsideDown;
			default: return UIInterfaceOrientationPortrait;
		}
	}

	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
		return UIInterfaceOrientationMaskAll;

	return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotate
{
	return !self.isAnimatingPresentationOrDismissal;
}

- (void)viewDidLayoutSubviews
{
	[self updateLayoutsForCurrentOrientation];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if (self.lastUsedOrientation != [UIApplication sharedApplication].statusBarOrientation)
	{
		self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
		self.rotationTransformDirty = YES;
		[self updateLayoutsForCurrentOrientation];
	}
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
								duration:(NSTimeInterval)duration
{
	self.lastUsedOrientation = toInterfaceOrientation;
	self.rotationTransformDirty = YES;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
										 duration:(NSTimeInterval)duration
{
	[self cancelCurrentImageDrag:NO];
	[self updateLayoutsForCurrentOrientation];
}

- (void)viewWillTransitionToSize:(CGSize)size
	   withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	self.rotationTransformDirty = YES;
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
		[self cancelCurrentImageDrag:NO];
		[self updateLayoutsForCurrentOrientation];
	} completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
		self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
	}];
}

- (void)deviceOrientationDidChange:(NSNotification *)notification
{
	NSString *systemVersion = [UIDevice currentDevice].systemVersion;
	if (systemVersion.floatValue < 8.0)
		return;
	/*
	 viewWillTransitionToSize:withTransitionCoordinator: is not called when rotating from
	 one landscape orientation to the other (or from one portrait orientation to another).
	 This makes it difficult to preserve the desired behavior of JTSImageViewController.
	 We want the background snapshot to maintain the illusion that it never rotates. The
	 only other way to ensure that the background snapshot stays in the correct orientation
	 is to listen for this notification and respond when we've detected a landscape-to-landscape rotation.
	 */
	UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
	BOOL landscapeToLandscape = UIDeviceOrientationIsLandscape(deviceOrientation) && UIInterfaceOrientationIsLandscape(self.lastUsedOrientation);
	BOOL portraitToPortrait = UIDeviceOrientationIsPortrait(deviceOrientation) && UIInterfaceOrientationIsPortrait(self.lastUsedOrientation);
	if (landscapeToLandscape || portraitToPortrait)
	{
		UIInterfaceOrientation newInterfaceOrientation = (UIInterfaceOrientation)deviceOrientation;
		if (newInterfaceOrientation != self.lastUsedOrientation)
		{
			self.lastUsedOrientation = newInterfaceOrientation;
			self.rotationTransformDirty = YES;
			[UIView animateWithDuration:0.6 animations:^{
				[self cancelCurrentImageDrag:NO];
				[self updateLayoutsForCurrentOrientation];
			} completion:nil];
		}
	}
}

- (void)dismissByCleaningUpAfterFlickOffscreen
{
	self.view.userInteractionEnabled = NO;
	self.animatingPresentationOrDismissal = YES ;

	[UIView animateWithDuration:kSLTTransitionAnimationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
		self.view.alpha = 0.f;
	} completion:^(BOOL finished) {
		id<SLTImgViewerVCDismissDelegate> dismissDelegate = self.dismissDelegate;
		[dismissDelegate imageViewerDidDismiss:self];
	}];
}

- (void)dismissByExpandingToOffscreenPosition
{
	self.view.userInteractionEnabled = NO;
	self.animatingPresentationOrDismissal = YES;

	[UIView animateWithDuration:kSLTTransitionAnimationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
		self.view.alpha = 0.f;
		self.scrollView.transform = CGAffineTransformMakeScale(kSLTMaxScalingForExpandingOffscreenStyleTransition,
															   kSLTMaxScalingForExpandingOffscreenStyleTransition);
	} completion:^(BOOL finished) {
		id<SLTImgViewerVCDismissDelegate> dismissDelegate = self.dismissDelegate;
		[dismissDelegate imageViewerDidDismiss:self];
	}];
}

- (void)dismissByFade
{
	self.view.userInteractionEnabled = NO;
	self.presented = NO;
	self.animatingPresentationOrDismissal = YES;

	[UIView animateWithDuration:kSLTTransitionAnimationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
		self.view.alpha = 0.f;
	} completion:^(BOOL finished) {
		id<SLTImgViewerVCDismissDelegate> dismissDelegate = self.dismissDelegate;
		[dismissDelegate imageViewerDidDismiss:self];
	}];
}

- (void)updateInterfaceWithImage:(UIImage *)image
{
	if (image)
	{
		self.image = image;
		self.imageView.image = image;

		if (!self.isDraggingImage)
		{
			[self updateLayoutsForCurrentOrientation];
		}
	}
}

- (void)updateLayoutsForCurrentOrientation
{
	[self updateScrollViewAndImageViewForCurrentMetrics];
	if (self.isRotationTransformDirty)
	{
		self.rotationTransformDirty = NO;
		if (self.isPresented)
		{
			self.scrollView.frame = self.view.bounds;
		}
	}
}

- (void)updateScrollViewAndImageViewForCurrentMetrics
{
	if (!self.isAnimatingPresentationOrDismissal)
	{
		self.scrollView.frame = self.view.bounds;
	}

	self.imageView.frame = [self resizedFrameForAutorotatingImageView:self.image.size];
	self.scrollView.contentSize = self.imageView.frame.size;
	self.scrollView.contentInset = [self contentInsetForScrollView:self.scrollView.zoomScale];
}

- (UIEdgeInsets)contentInsetForScrollView:(CGFloat)targetZoomScale
{
	UIEdgeInsets inset = UIEdgeInsetsZero;
	CGFloat boundsHeight = self.scrollView.bounds.size.height;
	CGFloat boundsWidth = self.scrollView.bounds.size.width;
	CGFloat contentHeight = (self.image.size.height > 0) ? self.image.size.height : boundsHeight;
	CGFloat contentWidth = (self.image.size.width > 0) ? self.image.size.width : boundsWidth;
	CGFloat minContentHeight;
	CGFloat minContentWidth;
	if (contentHeight > contentWidth)
	{
		if (boundsHeight/boundsWidth < contentHeight/contentWidth)
		{
			minContentHeight = boundsHeight;
			minContentWidth = contentWidth * (minContentHeight / contentHeight);
		}
		else
		{
			minContentWidth = boundsWidth;
			minContentHeight = contentHeight * (minContentWidth / contentWidth);
		}
	}
	else
	{
		if (boundsWidth/boundsHeight < contentWidth/contentHeight)
		{
			minContentWidth = boundsWidth;
			minContentHeight = contentHeight * (minContentWidth / contentWidth);
		}
		else
		{
			minContentHeight = boundsHeight;
			minContentWidth = contentWidth * (minContentHeight / contentHeight);
		}
	}
	CGFloat myHeight = self.view.bounds.size.height;
	CGFloat myWidth = self.view.bounds.size.width;
	minContentWidth *= targetZoomScale;
	minContentHeight *= targetZoomScale;
	if (minContentHeight > myHeight && minContentWidth > myWidth)
	{
		inset = UIEdgeInsetsZero;
	}
	else
	{
		CGFloat verticalDiff = boundsHeight - minContentHeight;
		CGFloat horizontalDiff = boundsWidth - minContentWidth;
		verticalDiff = (verticalDiff > 0) ? verticalDiff : 0;
		horizontalDiff = (horizontalDiff > 0) ? horizontalDiff : 0;
		inset.top = verticalDiff/2.0f;
		inset.bottom = verticalDiff/2.0f;
		inset.left = horizontalDiff/2.0f;
		inset.right = horizontalDiff/2.0f;
	}
	return inset;
}

- (CGRect)resizedFrameForAutorotatingImageView:(CGSize)imageSize
{
	CGRect frame = self.view.bounds;
	CGFloat screenWidth = frame.size.width * self.scrollView.zoomScale;
	CGFloat screenHeight = frame.size.height * self.scrollView.zoomScale;
	CGFloat targetWidth = screenWidth;
	CGFloat targetHeight = screenHeight;
	CGFloat nativeHeight = screenHeight;
	CGFloat nativeWidth = screenWidth;
	if (imageSize.width > 0 && imageSize.height > 0)
	{
		nativeHeight = (imageSize.height > 0) ? imageSize.height : screenHeight;
		nativeWidth = (imageSize.width > 0) ? imageSize.width : screenWidth;
	}
	if (nativeHeight > nativeWidth)
	{
		if (screenHeight/screenWidth < nativeHeight/nativeWidth)
		{
			targetWidth = screenHeight / (nativeHeight / nativeWidth);
		}
		else
		{
			targetHeight = screenWidth / (nativeWidth / nativeHeight);
		}
	}
	else
	{
		if (screenWidth/screenHeight < nativeWidth/nativeHeight)
		{
			targetHeight = screenWidth / (nativeWidth / nativeHeight);
		}
		else
		{
			targetWidth = screenHeight / (nativeHeight / nativeWidth);
		}
	}
	frame.size = CGSizeMake(targetWidth, targetHeight);
	frame.origin = CGPointMake(0, 0);
	return frame;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
	return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
	if (self.isImageFlickingAwayForDismissal)
		return;

	scrollView.contentInset = [self contentInsetForScrollView:scrollView.zoomScale];

	if (self.scrollView.scrollEnabled == NO)
		self.scrollView.scrollEnabled = YES;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView
					   withView:(UIView *)view
						atScale:(CGFloat)scale
{
	if (self.isImageFlickingAwayForDismissal)
		return;

	self.scrollView.scrollEnabled = (scale > 1);
	self.scrollView.contentInset = [self contentInsetForScrollView:scale];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
				  willDecelerate:(BOOL)decelerate
{
	if (self.isImageFlickingAwayForDismissal)
		return;

	CGPoint velocity = [scrollView.panGestureRecognizer velocityInView:scrollView.panGestureRecognizer.view];
	if (scrollView.zoomScale == 1 && fabs(velocity.y) > 1600)
	{
		[self dismissAnimated];
	}
}

- (void)imageDoubleTapped:(UITapGestureRecognizer *)sender
{
	if (self.isScrollViewAnimatingZoom)
		return;

	const CGPoint rawLocation = [sender locationInView:sender.view];
	const CGPoint point = [self.scrollView convertPoint:rawLocation fromView:sender.view];
	CGRect targetZoomRect;
	UIEdgeInsets targetInsets;
	if (self.scrollView.zoomScale == 1.0f)
	{
		CGFloat zoomWidth  = self.view.bounds.size.width  / kSLTTargetZoomForDoubleTap;
		CGFloat zoomHeight = self.view.bounds.size.height / kSLTTargetZoomForDoubleTap;
		targetZoomRect = CGRectMake(point.x - (zoomWidth / 2.f), point.y - (zoomHeight / 2.f), zoomWidth, zoomHeight);
		targetInsets = [self contentInsetForScrollView:kSLTTargetZoomForDoubleTap];
	}
	else
	{
		CGFloat zoomWidth  = self.view.bounds.size.width  * self.scrollView.zoomScale;
		CGFloat zoomHeight = self.view.bounds.size.height * self.scrollView.zoomScale;
		targetZoomRect = CGRectMake(point.x - (zoomWidth / 2.f), point.y - (zoomHeight / 2.f), zoomWidth, zoomHeight);
		targetInsets = [self contentInsetForScrollView:1.f];
	}
	self.view.userInteractionEnabled = NO;

	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		self.scrollView.contentInset = targetInsets;
		self.view.userInteractionEnabled = YES;
		self.scrollViewAnimatingZoom = NO;
	}];
	[self.scrollView zoomToRect:targetZoomRect animated:YES];
	[CATransaction commit];
}

- (void)imageSingleTapped:(id)sender
{
	if (self.isScrollViewAnimatingZoom)
		return;

	[self dismissAnimated];
}

- (void)dismissingPanGestureRecognizerPanned:(UIPanGestureRecognizer *)panner
{
	if (self.isScrollViewAnimatingZoom || self.isAnimatingPresentationOrDismissal)
		return;

	switch (panner.state)
	{
		case UIGestureRecognizerStateBegan:
		{
			self.panStartPoint = [panner locationInView:self.scrollView];
			self.panStartImageViewCenter = self.imageView.center;
			self.draggingImage = YES;
			[self updateAlphaBasedOnImageOffset];
		}
			break;
		case UIGestureRecognizerStateChanged:
		{
			const CGPoint translation = [panner translationInView:self.scrollView];
			self.imageView.center = CGPointMake(self.imageView.center.x, self.panStartImageViewCenter.y + translation.y);
			[self updateAlphaBasedOnImageOffset];

			const CGFloat maxOffsetToDismiss = [self maxImageViewOffsetToDismiss];
			const CGFloat currentOffset = ABS([self currentimageViewSignedOffset]);
			if (currentOffset >= maxOffsetToDismiss)
			{
				[self dismissByFade];
			}
		}
			break;
		case UIGestureRecognizerStateEnded:
		{
			const CGPoint velocity = [panner velocityInView:panner.view];
			if (fabs(velocity.y) > kSLTMinimumFlickDismissalVelocity)
			{
				if (self.isDraggingImage)
				{
					[self dismissImageWithFlick:velocity];
				}
				else
				{
					[self dismissAnimated];
				}
			}
			else
			{
				[self cancelCurrentImageDrag:YES];
			}
		}
			break;
		default:
			break;
	}
}

- (void)updateAlphaBasedOnImageOffset
{
	const CGFloat maxOffsetToDismiss = [self maxImageViewOffsetToDismiss];
	const CGFloat currentOffset = ABS([self currentimageViewSignedOffset]);
	const CGFloat ratio = MIN(currentOffset, maxOffsetToDismiss) / maxOffsetToDismiss;
	self.backgroundView.alpha = 1.f - 0.19f * ratio;
	self.imageView.alpha = 1.f - 0.085f * ratio;
}

- (CGFloat)maxImageViewOffsetToDismiss
{
	return self.view.bounds.size.height * 0.4f;
}

- (CGFloat)currentimageViewSignedOffset
{
	return self.imageView.center.y - self.scrollView.contentSize.height * 0.5f;
}

- (void)cancelCurrentImageDrag:(BOOL)animated
{
	self.draggingImage = NO;
	if (animated == NO)
	{
		self.imageView.transform = CGAffineTransformIdentity;
		self.imageView.center = CGPointMake(self.scrollView.contentSize.width  * 0.5f,
											self.scrollView.contentSize.height * 0.5f);
		[self updateAlphaBasedOnImageOffset];
	}
	else
	{
		[UIView animateWithDuration:0.5f
							  delay:0
			 usingSpringWithDamping:0.62f
			  initialSpringVelocity:0.f
							options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
							 if (!self.isDraggingImage)
							 {
								 self.imageView.transform = CGAffineTransformIdentity;
								 if (self.scrollView.dragging == NO && self.scrollView.decelerating == NO)
								 {
									 self.imageView.center = CGPointMake(self.scrollView.contentSize.width  * 0.5f,
																		 self.scrollView.contentSize.height * 0.5f);
									 [self updateScrollViewAndImageViewForCurrentMetrics];
									 [self updateAlphaBasedOnImageOffset];
								 }
							 }
						 }
						completion:nil];
	}
}

- (void)dismissImageWithFlick:(CGPoint)velocity
{
	self.imageFlickingAwayForDismissal = YES;
	const CGFloat duration = 0.2f;
	[UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
		self.imageView.center = CGPointMake(self.imageView.center.x, self.imageView.center.y + velocity.y * duration);
		[self updateAlphaBasedOnImageOffset];
	} completion:^(BOOL finished) {
		[self dismissAnimated];
	}];
}

- (CGFloat)appropriateAngularResistanceForView:(UIView *)view
{
	CGFloat height = view.bounds.size.height;
	CGFloat width = view.bounds.size.width;
	CGFloat actualArea = height * width;
	CGFloat referenceArea = self.view.bounds.size.width * self.view.bounds.size.height;
	CGFloat factor = referenceArea / actualArea;
	CGFloat defaultResistance = 4.0f; // Feels good with a 1x1 on 3.5 inch displays. We'll adjust this to match the current display.
	CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
	CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
	CGFloat resistance = defaultResistance * ((320.0 * 480.0) / (screenWidth * screenHeight));
	return resistance * factor;
}

- (CGFloat)appropriateDensityForView:(UIView *)view
{
	CGFloat height = view.bounds.size.height;
	CGFloat width = view.bounds.size.width;
	CGFloat actualArea = height * width;
	CGFloat referenceArea = self.view.bounds.size.width * self.view.bounds.size.height;
	CGFloat factor = referenceArea / actualArea;
	CGFloat defaultDensity = 0.5f; // Feels good on 3.5 inch displays. We'll adjust this to match the current display.
	CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
	CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
	CGFloat appropriateDensity = defaultDensity * ((320.0 * 480.0) / (screenWidth * screenHeight));
	return appropriateDensity * factor;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	if (gestureRecognizer == self.panRecognizer)
		return self.scrollView.zoomScale == 1 && !self.isScrollViewAnimatingZoom;
	return YES;
}

@end
