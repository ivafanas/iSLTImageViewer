#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@protocol SLTImgViewerVCDismissDelegate;


@interface SLTImgViewerVC : UIViewController
@property (nonatomic, copy, readonly) UIImage *img;
@property (nonatomic, weak) id<SLTImgViewerVCDismissDelegate> dismissDelegate;

- (instancetype)initWithImage:(UIImage *)img NS_DESIGNATED_INITIALIZER;
@end


@protocol SLTImgViewerVCDismissDelegate <NSObject>
@optional
- (void)imageViewerDidDismiss:(SLTImgViewerVC *)imageViewerVC;
@end
