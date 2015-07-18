# iSLTImageViewer
Yet another one image viewer for iOS.

## Description
The main idea is to be extra simple.
- No images downloading
- No errors reporting
- No status bar handling
- No only-modal-viewing!
- No text which does not fit in style of your app.

All of this is the responsibility of external code. And it is the choice of user.

Just view image. And do it gracefully.

[JTSImageViewController](https://github.com/jaredsinclair/JTSImageViewController) was used as initial implementation and significantly reduced with small number of bug fixes.

## Features
* View single image
* Scale images to zoom
* Dismiss by single tap or flicking away

## Usage example
Part of the code in parent view controller
```objective-c
- (void)showImage:(UIImage *)img
{
	SLTImgViewerVC *vc = [[SLTImgViewerVC alloc] initWithImage:img];
	vc.dismissDelegate = self;

	[vc willMoveToParentViewController:self];
	vc.view.frame = self.view.bounds;
	vc.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:vc.view];
	[self addChildViewController:vc];
}
```

## Requirements
* Tested on iOS 7.1 and higher

## License
MIT License
