#import "WMFArticleContainerViewController.h"
#import "WMFArticleContainerViewController_Transitioning.h"
#import <BlocksKit/BlocksKit+UIKit.h>

#import "Wikipedia-Swift.h"

// Frameworks
#import <Masonry/Masonry.h>

// Controller
#import "WMFArticleFetcher.h"
#import "WMFArticleViewController.h"
#import "WebViewController.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "WMFSaveButtonController.h"

// Model
#import "MWKDataStore.h"
#import "MWKArticle.h"
#import "MWKCitation.h"
#import "MWKTitle.h"
#import "MWKSavedPageList.h"
#import "MWKUserDataStore.h"
#import "MWKArticle+WMFSharing.h"
#import "MWKArticlePreview.h"

#import "WMFPreviewController.h"

//Sharing
#import "WMFShareFunnel.h"
#import "WMFShareOptionsController.h"

// Other
#import "SessionSingleton.h"
#import "UIBarButtonItem+WMFButtonConvenience.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFArticleContainerViewController ()
<WMFWebViewControllerDelegate, WMFArticleViewControllerDelegate, UINavigationControllerDelegate, WMFPreviewControllerDelegate>
@property (nonatomic, strong) MWKSavedPageList* savedPageList;
@property (nonatomic, strong) MWKDataStore* dataStore;

@property (nonatomic, strong) WMFArticlePreviewFetcher* articlePreviewFetcher;
@property (nonatomic, strong) WMFArticleFetcher* articleFetcher;
@property (nonatomic, strong, nullable) AnyPromise* articleFetcherPromise;

@property (nonatomic, strong) UINavigationController* contentNavigationController;
@property (nonatomic, strong, readwrite) WMFArticleViewController* articleViewController;
@property (nonatomic, strong, readwrite) WebViewController* webViewController;

@property (nonatomic, weak, readonly) UIViewController<WMFArticleContentController>* currentArticleController;

@property (nonatomic, strong, nullable) WMFPreviewController* previewController;

@property (strong, nonatomic, null_resettable) WMFShareFunnel* shareFunnel;
@property (strong, nonatomic, nullable) WMFShareOptionsController* shareOptionsController;
@property (strong, nonatomic) UIPopoverController* popover;

@property (nonatomic, strong) WMFSaveButtonController* saveButtonController;

@end

@implementation WMFArticleContainerViewController
@synthesize article = _article;

#pragma mark - Setup

+ (instancetype)articleContainerViewControllerWithDataStore:(MWKDataStore*)dataStore
                                                 savedPages:(MWKSavedPageList*)savedPages {
    return [[self alloc] initWithDataStore:dataStore savedPages:savedPages];
}

- (instancetype)initWithDataStore:(MWKDataStore*)dataStore savedPages:(MWKSavedPageList*)savedPages {
    self = [super init];
    if (self) {
        self.hidesBottomBarWhenPushed = YES;
        self.savedPageList            = savedPages;
        self.dataStore                = dataStore;
    }
    return self;
}

#pragma mark - Accessors

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %@", [super description], self.article.title];
}

- (UIViewController<WMFArticleContentController>*)currentArticleController {
    return (id)[self.contentNavigationController topViewController];
}

- (void)setArticle:(MWKArticle* __nullable)article {
    if (WMF_EQUAL(_article, isEqualToArticle:, article)) {
        return;
    }

    self.shareFunnel = nil;
    self.shareOptionsController = nil;
    
    // TODO cancel
    [self.articlePreviewFetcher cancelFetchForPageTitle:_article.title];
    [self.articleFetcher cancelFetchForPageTitle:_article.title];

    [self setAndObserveArticle:article];
    
    self.saveButtonController.title = article.title;
    
    if(_article){
        self.shareFunnel = [[WMFShareFunnel alloc] initWithArticle:_article];
        self.shareOptionsController =
        [[WMFShareOptionsController alloc] initWithArticle:self.article shareFunnel:self.shareFunnel];
    }
    
    [self fetchArticle];
}

- (void)setAndObserveArticle:(MWKArticle*)article{
    
    [self unobserveArticleUpdates];
    
    _article = article;
    
    [self observeArticleUpdates];
    
    //HACK: Need to check the window to see if we are on screen. http://stackoverflow.com/a/2777460/48311
    //isViewLoaded is not enough.
    if ([self isViewLoaded] && self.view.window) {
        self.articleViewController.article = article;
        self.webViewController.article     = article;
    }
}


- (WMFArticlePreviewFetcher*)articlePreviewFetcher {
    if (!_articlePreviewFetcher) {
        _articlePreviewFetcher = [[WMFArticlePreviewFetcher alloc] init];
    }
    return _articlePreviewFetcher;
}

- (WMFArticleFetcher*)articleFetcher {
    if (!_articleFetcher) {
        _articleFetcher = [[WMFArticleFetcher alloc] initWithDataStore:self.dataStore];
    }
    return _articleFetcher;
}

- (WMFArticleViewController*)articleViewController {
    if (!_articleViewController) {
        _articleViewController          = [WMFArticleViewController articleViewControllerWithDataStore:self.dataStore];
        _articleViewController.delegate = self;
    }
    return _articleViewController;
}

- (WebViewController*)webViewController {
    if (!_webViewController) {
        _webViewController          = [WebViewController wmf_initialViewControllerFromClassStoryboard];
        _webViewController.delegate = self;
    }
    return _webViewController;
}

#pragma mark - Article Notifications

- (void)observeArticleUpdates {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MWKArticleSavedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(articleUpdatedWithNotification:) name:MWKArticleSavedNotification object:nil];
}

- (void)unobserveArticleUpdates {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MWKArticleSavedNotification object:nil];
}

- (void)articleUpdatedWithNotification:(NSNotification*)note {
    dispatchOnMainQueue(^{
        MWKArticle* article = note.userInfo[MWKArticleKey];
        if ([self.article.title isEqualToTitle:article.title]) {
            [self setAndObserveArticle:article];
        }
    });
}


#pragma mark - ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupToolbar];

    // Manually adjusting scrollview offsets to compensate for embedded navigation controller
    self.automaticallyAdjustsScrollViewInsets = NO;

    [self updateInsetsForArticleViewController];

    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:self.articleViewController];
    nav.navigationBarHidden = YES;
    nav.delegate            = self;
    [self addChildViewController:nav];
    [self.view addSubview:nav.view];
    [nav.view mas_makeConstraints:^(MASConstraintMaker* make) {
        make.leading.trailing.top.and.bottom.equalTo(self.view);
    }];
    [nav didMoveToParentViewController:self];
    self.contentNavigationController = nav;

    if (self.article) {
        self.articleViewController.article = self.article;
        self.webViewController.article     = self.article;
    }
}

- (void)setupToolbar {
    @weakify(self)
    UIBarButtonItem * save = [UIBarButtonItem wmf_buttonType:WMFButtonTypeBookmark handler:^(id sender){
        @strongify(self)
        if (![self.article isCached]) {
            [self fetchArticle];
        }
    }];
    
    UIBarButtonItem * share = [UIBarButtonItem wmf_buttonType:WMFButtonTypeShare handler:^(id sender){
        @strongify(self)
        NSString* selectedText = nil;
        if(self.contentNavigationController.topViewController == self.webViewController){
            selectedText = [self.webViewController selectedText];
        }
        [self shareArticleWithTextSnippet:nil fromButton:sender];
    }];

    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL],
                          share,
                          [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL],
                          save];
    
    self.saveButtonController =
    [[WMFSaveButtonController alloc] initWithButton:[save wmf_UIButton]
                                      savedPageList:self.savedPageList
                                              title:self.article.title];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateInsetsForArticleViewController];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id < UIViewControllerTransitionCoordinatorContext > context) {
        [self updateInsetsForArticleViewController];
        [self.previewController updatePreviewWithSizeChange:size];
    } completion:NULL];
}

- (void)updateInsetsForArticleViewController {
    CGFloat topInset = [self.navigationController.navigationBar frame].size.height
                       + [[UIApplication sharedApplication] statusBarFrame].size.height;

    UIEdgeInsets adjustedInsets = UIEdgeInsetsMake(topInset,
                                                   0.0,
                                                   self.tabBarController.tabBar.frame.size.height,
                                                   0.0);

    self.articleViewController.tableView.contentInset          = adjustedInsets;
    self.articleViewController.tableView.scrollIndicatorInsets = adjustedInsets;

    //adjust offset if we are at the top
    if (self.articleViewController.tableView.contentOffset.y <= 0) {
        self.articleViewController.tableView.contentOffset = CGPointMake(0, -topInset);
    }
}


#pragma mark - Article Fetching

- (void)fetchArticle {
    [self fetchArticleForTitle:self.article.title];
}

- (void)fetchArticleForTitle:(MWKTitle*)title {
    @weakify(self);
    [self.articlePreviewFetcher fetchArticlePreviewForPageTitle:title progress:NULL].then(^(MWKArticlePreview* articlePreview){
        @strongify(self);
        [self unobserveArticleUpdates];
        AnyPromise* fullArticlePromise = [self.articleFetcher fetchArticleForPageTitle:title progress:NULL];
        self.articleFetcherPromise = fullArticlePromise;
        return fullArticlePromise;
    }).then(^(MWKArticle* article){
        @strongify(self);
        [self setAndObserveArticle:article];
    }).catch(^(NSError* error){
        @strongify(self);
        if ([error wmf_isWMFErrorOfType:WMFErrorTypeRedirected]) {
            [self fetchArticleForTitle:[[error userInfo] wmf_redirectTitle]];
        } else if (!self.presentingViewController) {
            // only do error handling if not presenting gallery
            DDLogError(@"Article Fetch Error: %@", [error localizedDescription]);
        }
    }).finally(^{
        @strongify(self);
        self.articleFetcherPromise = nil;
        [self observeArticleUpdates];
    });
}

#pragma mark - Share

- (void)shareArticleWithTextSnippet:(nullable NSString*)text fromButton:(nullable UIButton*)button{
    
    if(text.length == 0){
        text = [self.article shareSnippet];
    }
    
    [self.shareFunnel logShareButtonTappedResultingInSelection:text];
    [self.shareOptionsController presentShareOptionsWithSnippet:text inViewController:self fromView:button];
}

#pragma mark - WebView Transition

- (void)showWebViewAnimated:(BOOL)animated {
    [self.contentNavigationController pushViewController:self.webViewController animated:YES];
}

- (void)showWebViewAtFragment:(NSString*)fragment animated:(BOOL)animated {
    [self.webViewController scrollToFragment:fragment];
    [self showWebViewAnimated:animated];
}

#pragma mark - WMFArticleViewControllerDelegate

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
      didTapCitationLink:(NSString* __nonnull)citationFragment {
    if (self.article.isCached) {
        [self showCitationWithFragment:citationFragment];
    } else {
        // TODO: fetch all sections before attempting to parse citations natively
//        if (!self.articleFetcherPromise) {
//            [self fetchArticle];
//        }
//        @weakify(self);
//        self.articleFetcherPromise.then(^(MWKArticle* _) {
//            @strongify(self);
//            [self showCitationWithFragment:citationFragment];
//        });
    }
}

- (void)articleViewController:(WMFArticleViewController* __nonnull)articleViewController
    didTapSectionWithFragment:(NSString* __nonnull)fragment {
    [self showWebViewAtFragment:fragment animated:YES];
}

- (void)showCitationWithFragment:(NSString*)fragment {
    // TODO: parse citations natively, then show citation popup control
//    NSParameterAssert(self.article.isCached);
//    MWKCitation* tappedCitation = [self.article.citations bk_match:^BOOL (MWKCitation* citation) {
//        return [citation.citationIdentifier isEqualToString:fragment];
//    }];
//    DDLogInfo(@"Tapped citation %@", tappedCitation);
//    if (!tappedCitation) {
//        DDLogWarn(@"Failed to parse citation for article %@", self.article);
//    }

    // TEMP: show webview until we figure out what to do w/ ReferencesVC
    [self showWebViewAtFragment:fragment animated:YES];
}

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
        didTapLinkToPage:(MWKTitle* __nonnull)title {
    [self presentPopupForTitle:title];
}

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
      didTapExternalLink:(NSURL* __nonnull)externalURL {
    [[[SessionSingleton sharedInstance] zeroConfigState] showWarningIfNeededBeforeOpeningURL:externalURL];
}

#pragma mark - WMFArticleListItemController

- (WMFArticleControllerMode)mode {
    // TEMP: WebVC (and currentArticleController) will eventually conform to this
    return self.articleViewController.mode;
}

- (void)setMode:(WMFArticleControllerMode)mode animated:(BOOL)animated {
    // TEMP: WebVC (and currentArticleController) will eventually conform to this
    [self.articleViewController setMode:mode animated:animated];
}

#pragma mark - WMFWebViewControllerDelegate

- (void)webViewController:(WebViewController*)controller didTapOnLinkForTitle:(MWKTitle*)title {
    [self presentPopupForTitle:title];
}

- (void)webViewController:(WebViewController*)controller didSelectText:(NSString*)text{
    [self.shareFunnel logHighlight];
}

- (void)webViewController:(WebViewController*)controller didTapShareWithSelectedText:(NSString*)text{
    [self shareArticleWithTextSnippet:text fromButton:nil];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController*)navigationController willShowViewController:(UIViewController*)viewController animated:(BOOL)animated {
    if (viewController == self.articleViewController) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
        [self.contentNavigationController setNavigationBarHidden:YES animated:NO];
    } else {
        [self.navigationController setNavigationBarHidden:YES animated:NO];
        [self.contentNavigationController setNavigationBarHidden:NO animated:NO];
    }
}

#pragma mark - Popup

- (void)presentPopupForTitle:(MWKTitle*)title {
    MWKArticle* article = [self.dataStore articleWithTitle:title];

    WMFArticleContainerViewController* vc =
        [[WMFArticleContainerViewController alloc] initWithDataStore:self.dataStore
                                                          savedPages:self.savedPageList];
    vc.article = article;

    //TODO: Disabling pop ups until Popup VC is redesigned.
    //Renable preview when this true

    [self.navigationController pushViewController:vc animated:YES];

    return;

    WMFPreviewController* previewController = [[WMFPreviewController alloc] initWithPreviewViewController:vc containingViewController:self tabBarController:self.navigationController.tabBarController];
    previewController.delegate = self;
    [previewController presentPreviewAnimated:YES];

    self.previewController = previewController;
}

#pragma mark - Analytics

- (NSString*)analyticsName {
    return [self.articleViewController analyticsName];
}

#pragma mark - WMFPreviewControllerDelegate

- (void)previewController:(WMFPreviewController*)previewController didPresentViewController:(UIViewController*)viewController {
    self.previewController = nil;

    /* HACK: for some reason, the view controller is unusable when it comes back from the preview.
     * Trying to display it causes much ballyhooing about constraints.
     * Work around, make another view controller and push it instead.
     */
    WMFArticleContainerViewController* previewed = (id)viewController;

    WMFArticleContainerViewController* vc =
        [[WMFArticleContainerViewController alloc] initWithDataStore:self.dataStore
                                                          savedPages:self.savedPageList];
    vc.article = previewed.article;
    [self.navigationController pushViewController:vc animated:NO];
}

- (void)previewController:(WMFPreviewController*)previewController didDismissViewController:(UIViewController*)viewController {
    self.previewController = nil;
}


@end

NS_ASSUME_NONNULL_END
