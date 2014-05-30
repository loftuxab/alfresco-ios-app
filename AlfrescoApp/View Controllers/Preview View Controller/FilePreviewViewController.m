//
//  FilePreviewViewController.m
//  AlfrescoApp
//
//  Created by Tauseef Mughal on 03/04/2014.
//  Copyright (c) 2014 Alfresco. All rights reserved.
//

#import <MediaPlayer/MediaPlayer.h>

#import "FilePreviewViewController.h"
#import "ThumbnailImageView.h"
#import "ThumbnailManager.h"
#import "ErrorDescriptions.h"
#import "NavigationViewController.h"
#import "DocumentPreviewManager.h"
#import "FullScreenAnimationController.h"
#import "MBProgressHUD.h"

static CGFloat const kAnimationSpeed = 0.2f;
static CGFloat const kAnimationFadeSpeed = 0.5f;
static CGFloat downloadProgressHeight;
static CGFloat const kPlaceholderToProcessVerticalOffset = 30.0f;

@interface FilePreviewViewController () <UIWebViewDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate>

// Constraints
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *heightForDownloadContainer;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *centerYAlignmentForProgressContainer;

// Data Models
@property (nonatomic, strong) AlfrescoDocument *document;
@property (nonatomic, strong) id<AlfrescoSession> session;
@property (nonatomic, strong) AlfrescoRequest *downloadRequest;
@property (nonatomic, strong) MPMoviePlayerController *mediaPlayerController;
@property (nonatomic, strong) FullScreenAnimationController *animationController;
// Used for the file path initialiser
@property (nonatomic, assign) BOOL shouldLoadFromFileAndRunCompletionBlock;
@property (nonatomic, strong) NSString *filePathForFileToLoad;
@property (nonatomic, copy) void (^loadingCompleteBlock)(UIWebView *webView, BOOL loadedIntoWebView);
@property (nonatomic, assign) BOOL fullScreenMode;

// IBOutlets
@property (nonatomic, weak) IBOutlet ThumbnailImageView *previewThumbnailImageView;
@property (nonatomic, weak) IBOutlet UIWebView *webView;
@property (nonatomic, weak) IBOutlet UIProgressView *downloadProgressView;
@property (nonatomic, weak) IBOutlet UIView *downloadProgressContainer;
@property (nonatomic, weak) IBOutlet UIView *moviePlayerContainer;
// Views
@property (nonatomic, strong) MBProgressHUD *progressHUD;

@property (nonatomic, strong) UIGestureRecognizer *previewThumbnailSingleTapRecognizer;

@end

@implementation FilePreviewViewController

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editingDocumentCompleted:) name:kAlfrescoDocumentEditedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadStarting:) name:kDocumentPreviewManagerWillStartDownloadNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadProgress:) name:kDocumentPreviewManagerProgressNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadComplete:) name:kDocumentPreviewManagerDocumentDownloadCompletedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileLocallyUpdated:) name:kAlfrescoSaveBackLocalComplete object:nil];
    }
    return self;
}

- (instancetype)initWithDocument:(AlfrescoDocument *)document session:(id<AlfrescoSession>)session
{
    self = [self init];
    if (self)
    {
        self.document = document;
        self.session = session;
        self.animationController = [[FullScreenAnimationController alloc] init];
    }
    return self;
}

- (instancetype)initWithFilePath:(NSString *)filePath document:(AlfrescoDocument *)document loadingCompletionBlock:(void (^)(UIWebView *, BOOL))loadingCompleteBlock
{
    self = [self init];
    if (self)
    {
        self.filePathForFileToLoad = filePath;
        self.document = document;
        self.animationController = [[FullScreenAnimationController alloc] init];
        self.loadingCompleteBlock = loadingCompleteBlock;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self configureWebView];
    [self configureMediaPlayer];
    
    downloadProgressHeight = self.heightForDownloadContainer.constant;
    
    [self refreshViewController];
}

- (BOOL)prefersStatusBarHidden
{
    BOOL shouldHideStatusBar = NO;
    if (self.fullScreenMode)
    {
        shouldHideStatusBar = YES;
    }
    return shouldHideStatusBar;
}

#pragma mark - IBOutlets

- (IBAction)didPressCancelDownload:(id)sender
{
    [self.downloadRequest cancel];
    [self hideProgressViewAnimated:YES];
    self.downloadProgressView.progress = 0.0f;

    // Add single tap "re-download" action to thumbnail view
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThumbnailSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    singleTap.numberOfTouchesRequired = 1;
    self.previewThumbnailSingleTapRecognizer = singleTap;
    self.previewThumbnailImageView.userInteractionEnabled = YES;
    [self.previewThumbnailImageView addGestureRecognizer:singleTap];
}

#pragma mark - Private Functions

- (void)refreshViewController
{
    self.downloadProgressView.progress = 0.0f;
    
    [self hideLoadingProgressHUD];
    
    if (self.shouldLoadFromFileAndRunCompletionBlock)
    {
        [self displayFileAtPath:self.filePathForFileToLoad];
    }
    else
    {
        if ([[DocumentPreviewManager sharedManager] hasLocalContentOfDocument:self.document])
        {
            NSString *filePathToLoad = [[DocumentPreviewManager sharedManager] filePathForDocument:self.document];
            [self displayFileAtPath:filePathToLoad];
        }
        else
        {
            // Display a static placeholder image
            [self.previewThumbnailImageView setImage:largeImageForType(self.document.name.pathExtension) withFade:NO];
            
            // request the document download
            self.downloadRequest = [[DocumentPreviewManager sharedManager] downloadDocument:self.document session:self.session];
        }
    }
}

- (void)configureWebView
{
    self.webView.scalesPageToFit = YES;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor whiteColor];
    
    // Tap gestures
    // Single
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleWebViewSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    singleTap.numberOfTouchesRequired = 1;
    singleTap.delegate = self;
    [self.webView addGestureRecognizer:singleTap];
    // Double
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleWebViewDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.delegate = self;
    [self.webView addGestureRecognizer:doubleTap];
}

- (void)configureMediaPlayer
{
    MPMoviePlayerController *mediaPlayer = [[MPMoviePlayerController alloc] init];
    mediaPlayer.view.translatesAutoresizingMaskIntoConstraints = NO;
    mediaPlayer.view.backgroundColor = [UIColor clearColor];
    mediaPlayer.controlStyle = MPMovieControlStyleDefault;
    mediaPlayer.allowsAirPlay = YES;
    mediaPlayer.shouldAutoplay = NO;
    [mediaPlayer prepareToPlay];
    [self.moviePlayerContainer addSubview:mediaPlayer.view];
    
    // constraints
    NSDictionary *views = @{@"moviePlayerView" : mediaPlayer.view};
    [self.moviePlayerContainer addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[moviePlayerView]|"
                                                                                      options:NSLayoutFormatAlignAllBaseline
                                                                                      metrics:nil
                                                                                        views:views]];
    [self.moviePlayerContainer addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[moviePlayerView]|"
                                                                                      options:NSLayoutFormatAlignAllCenterX
                                                                                      metrics:nil
                                                                                        views:views]];
    self.mediaPlayerController = mediaPlayer;
}

- (void)handleThumbnailSingleTap:(UIGestureRecognizer *)gesture
{
    [self.previewThumbnailImageView removeGestureRecognizer:gesture];
    
    // Restart the document download
    self.downloadRequest = [[DocumentPreviewManager sharedManager] downloadDocument:self.document session:self.session];

}

- (void)handleWebViewSingleTap:(UIGestureRecognizer *)gesture
{
    if (self.presentingViewController)
    {
        if (self.navigationController.navigationBarHidden)
        {
            [self.navigationController setNavigationBarHidden:NO animated:YES];
        }
        else
        {
            [self.navigationController setNavigationBarHidden:YES animated:YES];
        }
    }
}

- (void)handleWebViewDoubleTap:(UIGestureRecognizer *)gesture
{
    if (!self.presentingViewController)
    {
        FilePreviewViewController *presentationViewController = nil;
        
        if (!self.shouldLoadFromFileAndRunCompletionBlock)
        {
            presentationViewController = [[FilePreviewViewController alloc] initWithDocument:self.document session:self.session];
        }
        else
        {
            presentationViewController = [[FilePreviewViewController alloc] initWithFilePath:self.filePathForFileToLoad document:nil loadingCompletionBlock:nil];
        }
        presentationViewController.fullScreenMode = YES;
        presentationViewController.useControllersPreferStatusBarHidden = YES;
        NavigationViewController *navigationPresentationViewController = [[NavigationViewController alloc] initWithRootViewController:presentationViewController];
        
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", @"Done")
                                                                       style:UIBarButtonItemStyleDone
                                                                      target:self
                                                                      action:@selector(dismiss:)];
        [presentationViewController.navigationItem setRightBarButtonItem:doneButton];
        presentationViewController.title = (self.document) ? self.document.name : self.filePathForFileToLoad.lastPathComponent;
        
        navigationPresentationViewController.transitioningDelegate  = self;
        navigationPresentationViewController.modalPresentationStyle = UIModalPresentationCustom;
        
        [self presentViewController:navigationPresentationViewController animated:YES completion:^{
            [presentationViewController.navigationController setNavigationBarHidden:YES animated:YES];
        }];
    }
}

- (void)dismiss:(UIBarButtonItem *)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showWebViewAnimated:(BOOL)animated
{
    if (animated)
    {
        self.webView.alpha = 0.0f;
        self.webView.hidden = NO;
        [UIView animateWithDuration:kAnimationFadeSpeed animations:^{
            self.previewThumbnailImageView.alpha = 0.0f;
            self.webView.alpha = 1.0f;
        }];
    }
    else
    {
        self.webView.hidden = NO;
    }
}

- (void)hideWebViewAnimated:(BOOL)animated
{
    if (animated)
    {
        self.webView.hidden = YES;
        [UIView animateWithDuration:kAnimationFadeSpeed animations:^{
            self.previewThumbnailImageView.alpha = 0.0f;
            self.webView.alpha = 0.0f;
        }];
    }
    else
    {
        self.webView.hidden = YES;
    }
}

- (void)showMediaPlayerAnimated:(BOOL)animated
{
    if (animated)
    {
        self.moviePlayerContainer.alpha = 0.0f;
        self.moviePlayerContainer.hidden = NO;
        [UIView animateWithDuration:kAnimationFadeSpeed animations:^{
            self.previewThumbnailImageView.alpha = 0.0f;
            self.moviePlayerContainer.alpha = 1.0f;
        }];
    }
    else
    {
        self.moviePlayerContainer.hidden = NO;
    }
}

- (void)hideMediaPlayerAnimated:(BOOL)animated
{
    if (animated)
    {
        self.moviePlayerContainer.hidden = YES;
        [UIView animateWithDuration:kAnimationFadeSpeed animations:^{
            self.previewThumbnailImageView.alpha = 0.0f;
            self.moviePlayerContainer.alpha = 0.0f;
        }];
    }
    else
    {
        self.moviePlayerContainer.hidden = YES;
    }
}

- (void)requestThumbnailForDocument:(AlfrescoDocument *)document completionBlock:(ImageCompletionBlock)completionBlock
{
    [[ThumbnailManager sharedManager] retrieveImageForDocument:self.document renditionType:kRenditionImageImagePreview session:self.session completionBlock:^(UIImage *image, NSError *error) {
        if (completionBlock != NULL)
        {
            completionBlock(image, error);
        }
    }];
}

- (void)showProgressViewAnimated:(BOOL)animated
{
    if (animated)
    {
        [self.downloadProgressContainer layoutIfNeeded];
        [UIView animateWithDuration:kAnimationSpeed delay:0.0f options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.heightForDownloadContainer.constant = downloadProgressHeight;
            self.centerYAlignmentForProgressContainer.constant = (self.previewThumbnailImageView.image.size.height / 2) + kPlaceholderToProcessVerticalOffset;
            [self.downloadProgressContainer layoutIfNeeded];
        } completion:nil];
    }
    else
    {
        self.heightForDownloadContainer.constant = downloadProgressHeight;
        self.centerYAlignmentForProgressContainer.constant = (self.previewThumbnailImageView.image.size.height / 2) + kPlaceholderToProcessVerticalOffset;
    }
    self.downloadProgressContainer.hidden = NO;
}

- (void)hideProgressViewAnimated:(BOOL)animated
{
    if (animated)
    {
        [self.downloadProgressContainer layoutIfNeeded];
        [UIView animateWithDuration:kAnimationSpeed delay:0.5f options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.heightForDownloadContainer.constant = 0;
            [self.downloadProgressContainer layoutIfNeeded];
        } completion:nil];
    }
    else
    {
        self.heightForDownloadContainer.constant = 0;
    }
    self.downloadProgressContainer.hidden = YES;
}

- (void)displayFileAtPath:(NSString *)filePathToDisplay
{
    [self hideProgressViewAnimated:YES];
    
    if ([Utility isAudioOrVideo:filePathToDisplay])
    {
        self.mediaPlayerController.contentURL = [NSURL fileURLWithPath:filePathToDisplay];
        
        [self.mediaPlayerController prepareToPlay];
        
        [self showMediaPlayerAnimated:YES];
    }
    else
    {
        [self showLoadingProgressHUDAfterDelayInSeconds:1];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:filePathToDisplay]]];
    }
}

- (void)showLoadingProgressHUDAfterDelayInSeconds:(float)seconds
{
    self.progressHUD = [[MBProgressHUD alloc] initWithView:self.view];
    self.progressHUD.detailsLabelText = NSLocalizedString(@"file.preview.loading.document.from.file", @"Loading Document");
    [self.view addSubview:self.progressHUD];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.progressHUD show:YES];
    });
}

- (void)hideLoadingProgressHUD
{
    [self.progressHUD hide:YES];
    self.progressHUD = nil;
}

#pragma mark - DocumentPreviewManager Notification Callbacks

- (void)downloadStarting:(NSNotification *)notification
{
    NSString *displayedDocumentIdentifier = [[DocumentPreviewManager sharedManager] documentIdentifierForDocument:self.document];
    NSString *notificationDocumentIdentifier = notification.userInfo[kDocumentPreviewManagerDocumentIdentifierNotificationKey];
    
    if ([displayedDocumentIdentifier isEqualToString:notificationDocumentIdentifier])
    {
        self.previewThumbnailImageView.alpha = 1.0f;
        [self showProgressViewAnimated:YES];
    }
}

- (void)downloadProgress:(NSNotification *)notification
{
    NSString *displayedDocumentIdentifier = [[DocumentPreviewManager sharedManager] documentIdentifierForDocument:self.document];
    NSString *notificationDocumentIdentifier = notification.userInfo[kDocumentPreviewManagerDocumentIdentifierNotificationKey];
    
    if ([displayedDocumentIdentifier isEqualToString:notificationDocumentIdentifier])
    {
        if (self.downloadProgressContainer.hidden)
        {
            [self showProgressViewAnimated:YES];
        }
        
        unsigned long long bytesTransferred = [notification.userInfo[kDocumentPreviewManagerProgressBytesRecievedNotificationKey] unsignedLongLongValue];
        unsigned long long bytesTotal = [notification.userInfo[kDocumentPreviewManagerProgressBytesTotalNotificationKey] unsignedLongLongValue];
        
        [self.downloadProgressView setProgress:(float)bytesTransferred/(float)bytesTotal];
    }
}

- (void)downloadComplete:(NSNotification *)notification
{
    NSString *displayedDocumentIdentifier = [[DocumentPreviewManager sharedManager] documentIdentifierForDocument:self.document];
    NSString *notificationDocumentIdentifier = notification.userInfo[kDocumentPreviewManagerDocumentIdentifierNotificationKey];
    
    if ([displayedDocumentIdentifier isEqualToString:notificationDocumentIdentifier])
    {
        [self hideProgressViewAnimated:YES];
        [self displayFileAtPath:[[DocumentPreviewManager sharedManager] filePathForDocument:self.document]];
    }
}

- (void)fileLocallyUpdated:(NSNotification *)notification
{
    NSString *nodeRefUpdated = notification.object;
    
    if ([nodeRefUpdated isEqualToString:self.document.identifier] || self.document == nil)
    {
        [self.webView reload];
    }
}

#pragma mark - Document Editing Notification

- (void)editingDocumentCompleted:(NSNotification *)notification
{
    [self refreshViewController];
}

#pragma mark - UIWebViewDelegate Functions

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (!self.downloadProgressContainer.hidden)
    {
        [self hideProgressViewAnimated:YES];
    }
    
    if (self.webView.hidden)
    {
        [self showWebViewAnimated:YES];
    }
    
    if (self.progressHUD)
    {
        [self hideLoadingProgressHUD];
    }
    
    if (self.shouldLoadFromFileAndRunCompletionBlock && self.loadingCompleteBlock != NULL)
    {
        self.loadingCompleteBlock(webView, YES);
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self.previewThumbnailImageView setImage:largeImageForType(self.document.name.pathExtension) withFade:NO];
    self.previewThumbnailImageView.alpha = 1.0f;
    
    if (self.progressHUD)
    {
        [self hideLoadingProgressHUD];
    }

    if (self.shouldLoadFromFileAndRunCompletionBlock && self.loadingCompleteBlock != NULL)
    {
        self.loadingCompleteBlock(nil, NO);
    }
}

#pragma mark - UIGestureRecognizerDelegate Functions

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

#pragma mark - UIViewControllerAnimatedTransitioning Functions

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    self.animationController.isGoingIntoFullscreenMode = YES;
    return self.animationController;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    self.animationController.isGoingIntoFullscreenMode = NO;
    return self.animationController;
}

#pragma mark - NodeUpdatableProtocol Functions

- (void)updateToAlfrescoDocument:(AlfrescoDocument *)node permissions:(AlfrescoPermissions *)permissions contentFilePath:(NSString *)contentFilePath documentLocation:(InAppDocumentLocation)documentLocation session:(id<AlfrescoSession>)session
{
    self.document = (AlfrescoDocument *)node;
    self.filePathForFileToLoad = contentFilePath;
    self.session = session;
    
    [self hideWebViewAnimated:NO];
    [self hideMediaPlayerAnimated:NO];
    [self showProgressViewAnimated:NO];
    
    [self refreshViewController];
}

@end
