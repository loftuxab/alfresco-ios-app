/*******************************************************************************
 * Copyright (C) 2005-2015 Alfresco Software Limited.
 *
 * This file is part of the Alfresco Mobile iOS App.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 ******************************************************************************/

#import "DocumentPickerViewController.h"
#import "UserAccount.h"
#import "UserAccountWrapper.h"
#import "KeychainUtils.h"
#import "AppConfiguration.h"
#import "SharedConstants.h"
#import "CustomFolderService.h"
#import "MBProgressHUD.h"
#import "AlfrescoFileManager+Extensions.h"
#import "NSFileManager+Extension.h"
#import "FileMetadata.h"
#import "PersistentQueueStore.h"
#import "Utilities.h"

static NSString * const kAccountsListIdentifier = @"AccountListNew";

@interface DocumentPickerViewController () <AKUserAccountListViewControllerDelegate,
                                            AKAlfrescoNodePickingListViewControllerDelegate,
                                            AKScopePickingViewControllerDelegate,
                                            AKSitesListViewControllerDelegate,
                                            AKLoginViewControllerDelegate,
                                            AKNamingViewControllerDelegate,
                                            AKLocalFilesViewControllerDelegate,
                                            AKFavoritesListViewControllerDelegate>

@property (nonatomic, weak) IBOutlet UIView *containingView;
@property (nonatomic, strong) id<AlfrescoSession> session;
@property (nonatomic, strong) id<AKUserAccount> account;
@property (nonatomic, strong) UINavigationController *embeddedNavigationController;
@property (nonatomic, strong) PersistentQueueStore *queueStore;

@end

@implementation DocumentPickerViewController

-(void)prepareForPresentationInMode:(UIDocumentPickerMode)mode
{
    NSError *keychainError = nil;
    NSArray *savedAccounts = [KeychainUtils savedAccountsForListIdentifier:kAccountsListIdentifier error:&keychainError];
    
    if (keychainError)
    {
        AlfrescoLogError(@"Error accessing shared keychain. Error: %@", keychainError.localizedDescription);
    }
    
    // Create wrapper accounts
    NSArray *wrapperAccounts = [self createAlfrescoKitUserAccountsFromAppAccounts:savedAccounts];
    // Display the accounts controller
    AKUserAccountListViewController *userAccountViewController = [[AKUserAccountListViewController alloc] initWithAccountList:wrapperAccounts delegate:self];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:userAccountViewController];
    self.embeddedNavigationController = navigationController;
    [self setRootEmbeddedController:navigationController];
}

#pragma mark - Custom Getters and Setters

- (PersistentQueueStore *)queueStore
{
    if (!_queueStore)
    {
        _queueStore = [[PersistentQueueStore alloc] initWithGroupContainerIdentifier:kSharedAppGroupIdentifier];
    }
    return _queueStore;
}

#pragma mark - Private Methods

- (void)setRootEmbeddedController:(UIViewController *)controller
{
    [self addChildViewController:controller];
    [self.containingView addSubview:controller.view];
    // Constraints
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *view = @{@"childView" : controller.view};
    NSArray *vertical = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[childView]|" options:NSLayoutFormatAlignAllBaseline metrics:nil views:view];
    NSArray *horizontal = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[childView]|" options:NSLayoutFormatAlignAllBaseline metrics:nil views:view];
    [self.containingView addConstraints:vertical];
    [self.containingView addConstraints:horizontal];
    [controller didMoveToParentViewController:self];
}

- (NSArray *)createAlfrescoKitUserAccountsFromAppAccounts:(NSArray *)userAccounts
{
    NSMutableArray *returnAccounts = [NSMutableArray arrayWithCapacity:userAccounts.count];
    
    for (UserAccount *account in userAccounts)
    {
        UserAccountWrapper *wrapperAccount = [[UserAccountWrapper alloc] initWithUserAccount:account];
        [returnAccounts addObject:wrapperAccount];
    }
    
    return returnAccounts;
}

- (NSURL *)configurationFileNameURLForAccount:(id<AKUserAccount>)account
{
    NSString *accountIdentifier = account.identifier;
    
    if (!account.isOnPremiseAccount)
    {
        accountIdentifier = [NSString stringWithFormat:@"%@-%@", accountIdentifier, account.selectedNetworkIdentifier];
    }
    
    NSString *configurationFileName = [accountIdentifier stringByAppendingPathExtension:[kAppConfigurationFileLocationOnServer pathExtension]];
    NSURL *sharedContainerURL = [[NSFileManager alloc] containerURLForSecurityApplicationGroupIdentifier:kSharedAppGroupIdentifier];
    NSString *filePath = [sharedContainerURL.path stringByAppendingPathComponent:configurationFileName];
    
    return [NSURL fileURLWithPath:filePath];
}

- (NSArray *)scopeItemsForAccount:(id<AKUserAccount>)account myFilesFolder:(AlfrescoFolder *)myFilesFolder sharedFilesFolder:(AlfrescoFolder *)sharedFilesFolder
{
    // Default visibility
    BOOL showRepository = YES;
    BOOL showSites = YES;
    BOOL showFavourites = YES;
    BOOL showSharedFiles = !!sharedFilesFolder;
    BOOL showMyFiles = !!myFilesFolder;
    
    NSURL *configFilePathURL = [self configurationFileNameURLForAccount:account];
    BOOL appConfigurationFileExists = [[NSFileManager defaultManager] fileExistsAtPath:configFilePathURL.path];
    if (appConfigurationFileExists)
    {
        AppConfiguration *configuration = [[AppConfiguration alloc] initWithAppConfigurationFileURL:configFilePathURL];
        showRepository = [configuration visibilityInRootMenuForKey:kAppConfigurationRepositoryKey];
        showSites = [configuration visibilityInRootMenuForKey:kAppConfigurationSitesKey];
        showFavourites = [configuration visibilityInRootMenuForKey:kAppConfigurationFavoritesKey];
    }
    
    NSMutableArray *scopeItems = [NSMutableArray array];
    
    if (showRepository)
    {
        AKScopeItem *repoScope = [[AKScopeItem alloc] initWithIdentifier:kAppConfigurationRepositoryKey
                                                                imageURL:nil
                                                                    name:NSLocalizedString(@"document.picker.scope.repository", @"Respository")];
        [scopeItems addObject:repoScope];
    }
    if (showSites)
    {
        AKScopeItem *siteScope = [[AKScopeItem alloc] initWithIdentifier:kAppConfigurationSitesKey
                                                                imageURL:nil
                                                                    name:NSLocalizedString(@"document.picker.scope.sites", @"Sites")];
        [scopeItems addObject:siteScope];
    }
    if (showFavourites)
    {
        AKScopeItem *favouriteScope = [[AKScopeItem alloc] initWithIdentifier:kAppConfigurationFavoritesKey
                                                                     imageURL:nil
                                                                         name:NSLocalizedString(@"document.picker.scope.favourites", @"Favourites")];
        [scopeItems addObject:favouriteScope];
    }
    if (showSharedFiles)
    {
        AKScopeItem *sharedFilesScope = [[AKScopeItem alloc] initWithIdentifier:kAppConfigurationSharedFilesKey
                                                                       imageURL:nil
                                                                           name:NSLocalizedString(@"document.picker.scope.shared.files", @"Shared Files")
                                                                       userInfo:sharedFilesFolder];
        [scopeItems addObject:sharedFilesScope];
    }
    if (showMyFiles)
    {
        AKScopeItem *myFilesScope = [[AKScopeItem alloc] initWithIdentifier:kAppConfigurationMyFilesKey
                                                                   imageURL:nil
                                                                       name:NSLocalizedString(@"document.picker.scope.my.files", @"My Files")
                                                                   userInfo:myFilesFolder];
        [scopeItems addObject:myFilesScope];
    }
    
    return scopeItems;
}

- (void)displayScopeViewControllerFromController:(UIViewController *)controller forAccount:(id<AKUserAccount>)account session:(id<AlfrescoSession>)session completionBlock:(void (^)())completionBlock
{
    self.account = account;
    self.session = session;
    
    void (^createAndPushScopeViewController)(NSArray *, id<AKScopePickingViewControllerDelegate>) = ^(NSArray *scopeItems, id<AKScopePickingViewControllerDelegate>scopeDelegate) {
        AKScopePickingViewController *scopePickingViewController = [[AKScopePickingViewController alloc] initWithScopeItems:scopeItems delegate:scopeDelegate];
        [self.embeddedNavigationController pushViewController:scopePickingViewController animated:YES];
        if (completionBlock != NULL)
        {
            completionBlock();
        }
    };
    
    // Show a progress indicator
    MBProgressHUD *spinner = [self spinningHUDForView:controller.view];
    [controller.view addSubview:spinner];
    [spinner show:YES];
    // Get shared and my file folders
    CustomFolderService *folderService = [[CustomFolderService alloc] initWithSession:session];
    [folderService retreiveMyFilesFolderWithCompletionBlock:^(AlfrescoFolder *myFilesFolder, NSError *error) {
        [folderService retreiveSharedFilesFolderWithCompletionBlock:^(AlfrescoFolder *sharedFilesFolder, NSError *error) {
            [spinner hide:YES];
            NSArray *scopeItems = [self scopeItemsForAccount:account myFilesFolder:myFilesFolder sharedFilesFolder:sharedFilesFolder];
            createAndPushScopeViewController(scopeItems, self);
        }];
    }];
}

- (MBProgressHUD *)spinningHUDForView:(UIView *)view
{
    MBProgressHUD *spinningHUD = [[MBProgressHUD alloc] initWithView:view];
    spinningHUD.removeFromSuperViewOnHide = YES;
    return spinningHUD;
}

- (MBProgressHUD *)progressHUDForView:(UIView *)view
{
    MBProgressHUD *progressHUD = [[MBProgressHUD alloc] initWithView:view];
    progressHUD.mode = MBProgressHUDModeDeterminate;
    progressHUD.progress = 0.0f;
    progressHUD.removeFromSuperViewOnHide = YES;
    return progressHUD;
}

- (void)displayErrorAlertWithTitle:(NSString *)title message:(NSString *)message error:(NSError *)error
{
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok") style:UIAlertActionStyleCancel handler:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
    
    AlfrescoLogError(@"Error: %@", error.localizedDescription);
}

#pragma mark - AKUserAccountListViewControllerDelegate Methods

- (void)userAccountListViewController:(AKUserAccountListViewController *)accountListViewController
                 didLoginSuccessfully:(BOOL)loginSuccessful
                            toAccount:(id<AKUserAccount>)account
                      creatingSession:(id<AlfrescoSession>)session
                                error:(NSError *)error
{
    if (loginSuccessful)
    {
        [self displayScopeViewControllerFromController:accountListViewController forAccount:account session:session completionBlock:nil];
    }
    else
    {
        AKLoginViewController *loginViewController = [[AKLoginViewController alloc] initWithUserAccount:account delegate:self];
        [self.embeddedNavigationController pushViewController:loginViewController animated:YES];
    }
}

- (void)didSelectLocalFilesOnUserAccountListViewController:(AKUserAccountListViewController *)accountListViewController
{
    AKLocalFileControllerType mode;
    
    if (self.documentPickerMode == UIDocumentPickerModeImport || self.documentPickerMode == UIDocumentPickerModeOpen)
    {
        mode = AKLocalFileControllerTypeFilePicker;
    }
    else
    {
        mode = AKLocalFileControllerTypeFolderPicker;
    }
    NSString *downloadContentPath = [[AlfrescoFileManager sharedManager] downloadsContentFolderPath];
    NSURL *downloadContentURL = [NSURL fileURLWithPath:downloadContentPath];
    AKLocalFilesViewController *localFileController = [[AKLocalFilesViewController alloc] initWithMode:mode url:downloadContentURL delegate:self];
    
    [self.embeddedNavigationController pushViewController:localFileController animated:YES];
}

#pragma mark Code used to handle selecting a document or a folder

- (void)handleSelectionFromController:(UIViewController *)controller selectedNodes:(NSArray *)selectedNodes
{
    AlfrescoDocument *document = selectedNodes.firstObject;
    NSString *uniqueFilename = [Utilities filenameWithVersionFromFilename:document.name nodeIdentifier:document.identifier];
    NSURL *outURL = [self.documentStorageURL URLByAppendingPathComponent:uniqueFilename];
    
    if (self.documentPickerMode == UIDocumentPickerModeImport)
    {
        // Show Progress HUD
        MBProgressHUD *progressHUD = [self progressHUDForView:controller.view];
        [controller.view addSubview:progressHUD];
        [progressHUD show:YES];
        
        NSOutputStream *outputStream = [NSOutputStream outputStreamWithURL:outURL append:NO];
        AlfrescoDocumentFolderService *docService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
        [docService retrieveContentOfDocument:document outputStream:outputStream completionBlock:^(BOOL succeeded, NSError *error) {
            [progressHUD hide:YES];
            if (error)
            {
                [self displayErrorAlertWithTitle:NSLocalizedString(@"Error", @"Error") message:error.localizedDescription error:error];
            }
            else
            {
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
                [coordinator coordinateWritingItemAtURL:outURL options:NSFileCoordinatorWritingForReplacing error:nil byAccessor:^(NSURL *newURL) {
                    NSFileManager *fileManager = [[NSFileManager alloc] init];
                    [fileManager setAttributes:@{NSFileModificationDate : document.modifiedAt} ofItemAtPath:outURL.path error:nil];
                    [fileManager copyItemAtURL:outURL toURL:newURL error:nil];
                }];
                
                [self dismissGrantingAccessToURL:outURL];
            }
        } progressBlock:^(unsigned long long bytesTransferred, unsigned long long bytesTotal) {
            progressHUD.progress = (bytesTotal != 0) ? (float)bytesTransferred / (float)bytesTotal : 0;
        }];
    }
    else if (self.documentPickerMode == UIDocumentPickerModeOpen)
    {
        // Show Progress HUD
        MBProgressHUD *progressHUD = [self progressHUDForView:controller.view];
        progressHUD.mode = MBProgressHUDModeIndeterminate;
        [controller.view addSubview:progressHUD];
        [progressHUD show:YES];
        
        // Retrieve Permissions
        AlfrescoDocumentFolderService *documentService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
        [documentService retrievePermissionsOfNode:document completionBlock:^(AlfrescoPermissions *permissions, NSError *error) {
            [progressHUD hide:YES];
            if (error)
            {
                [self displayErrorAlertWithTitle:NSLocalizedString(@"Error", @"Error") message:error.localizedDescription error:error];
            }
            else
            {
                void (^cacheAndDismissBlock)(FileMetadataSaveLocation saveLocation) = ^(FileMetadataSaveLocation location) {
                    NSArray *fileURLs = [self.queueStore.queue valueForKey:@"fileURL"];
                    
                    FileMetadata *metadata = [[FileMetadata alloc] initWithAccountIdentififer:self.account.identifier repositoryNode:document fileURL:outURL sourceLocation:location];
                    
                    if (![fileURLs containsObject:outURL])
                    {
                        [self.queueStore addObjectToQueue:metadata];
                        [self.queueStore saveQueue];
                    }
                    else
                    {
                        NSUInteger indexOfMetadata = [fileURLs indexOfObject:outURL];
                        [self.queueStore replaceObjectInQueueAtIndex:indexOfMetadata withObject:metadata];
                        [self.queueStore saveQueue];
                    }
                    
                    [self dismissGrantingAccessToURL:outURL];
                };
                
                if (permissions.canEdit)
                {
                    cacheAndDismissBlock(FileMetadataSaveLocationRepository);
                }
                else
                {
                    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", "Ok")
                                                                     style:UIAlertActionStyleCancel
                                                                   handler:^(UIAlertAction *action) {
                        cacheAndDismissBlock(FileMetadataSaveLocationLocalFiles);
                    }];
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"document.picker.scope.permissions.cannot.edit.title", "Permissions Error")
                                                                                   message:NSLocalizedString(@"document.picker.scope.permissions.cannot.edit.message", @"Permissions Message")
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:cancel];
                    [self presentViewController:alert animated:YES completion:nil];
                }
            }
        }];
        
        
    }
    else if (self.documentPickerMode == UIDocumentPickerModeExportToService || self.documentPickerMode == UIDocumentPickerModeMoveToService)
    {
        AlfrescoFolder *uploadFolder = selectedNodes.firstObject;
        AKNamingViewController *namingController = [[AKNamingViewController alloc] initWithURL:nil delegate:self userInfo:uploadFolder];
        [self.embeddedNavigationController pushViewController:namingController animated:YES];
    }
}

#pragma mark - AKLoginViewControllerDelegate Methods

- (void)loginViewController:(AKLoginViewController *)loginController
       didLoginSuccessfully:(BOOL)loginSuccessful
                  toAccount:(id<AKUserAccount>)account
                   username:(NSString *)username
                   password:(NSString *)password
            creatingSession:(id<AlfrescoSession>)session
                      error:(NSError *)error
{
    if (loginSuccessful)
    {
        [self displayScopeViewControllerFromController:loginController forAccount:account session:session completionBlock:^{
            // Remove the login controller from the nav stack
            NSMutableArray *navigationStack = self.embeddedNavigationController.viewControllers.mutableCopy;
            [navigationStack removeObjectAtIndex:(navigationStack.count-2)];
            self.embeddedNavigationController.viewControllers = navigationStack;
        }];
    }
    else
    {
        [self displayErrorAlertWithTitle:NSLocalizedString(@"Error", @"Error") message:error.localizedDescription error:error];
    }
}

#pragma mark - AKScopePickingViewControllerDelegate Methods

- (void)scopePickingController:(AKScopePickingViewController *)scopePickingController didSelectScopeItem:(AKScopeItem *)scopeItem
{
    UIViewController *pushController = nil;
    
    if ([scopeItem.identifier isEqualToString:kAppConfigurationRepositoryKey])
    {
        pushController = [self folderOrDocumentPickingViewControllerWithRootFolder:nil delegate:self session:self.session];
    }
    else if ([scopeItem.identifier isEqualToString:kAppConfigurationSitesKey])
    {
        pushController = [[AKSitesListViewController alloc] initWithSession:self.session delegate:self];
    }
    else if ([scopeItem.identifier isEqualToString:kAppConfigurationFavoritesKey])
    {
        pushController = [self favouritesViewControllerWithDelegate:self session:self.session];
    }
    else if ([scopeItem.identifier isEqualToString:kAppConfigurationMyFilesKey])
    {
        pushController = [self folderOrDocumentPickingViewControllerWithRootFolder:(AlfrescoFolder *)scopeItem.userInfo delegate:self session:self.session];
    }
    else if ([scopeItem.identifier isEqualToString:kAppConfigurationSharedFilesKey])
    {
        pushController = [self folderOrDocumentPickingViewControllerWithRootFolder:(AlfrescoFolder *)scopeItem.userInfo delegate:self session:self.session];
    }
    
    [self.embeddedNavigationController pushViewController:pushController animated:YES];
}

- (UIViewController *)folderOrDocumentPickingViewControllerWithRootFolder:(AlfrescoFolder *)folder delegate:(id)delegate session:(id<AlfrescoSession>)session
{
    UIViewController *returnController = nil;
    
    if (self.documentPickerMode == UIDocumentPickerModeImport || self.documentPickerMode == UIDocumentPickerModeOpen)
    {
        returnController = [[AKAlfrescoNodePickingListViewController alloc] initAlfrescoDocumentPickerWithRootFolder:folder multipleSelection:NO selectedNodes:nil delegate:self session:session];
    }
    else
    {
        returnController = [[AKAlfrescoNodePickingListViewController alloc] initAlfrescoFolderPickerWithRootFolder:folder selectedNodes:nil delegate:self session:session];
    }
    
    return returnController;
}

- (UIViewController *)favouritesViewControllerWithDelegate:(id<AKFavoritesListViewControllerDelegate>)delegate session:(id<AlfrescoSession>)session
{
    AKFavoritesControllerType type;
    if (self.documentPickerMode == UIDocumentPickerModeImport || self.documentPickerMode == UIDocumentPickerModeOpen)
    {
        type = AKFavoritesControllerTypeFilePicker;
    }
    else
    {
        type = AKFavoritesControllerTypeFolderPicker;
    }
    
    AKFavoritesListViewController *favouritesListViewController = [[AKFavoritesListViewController alloc] initWithMode:type delegate:delegate session:session];
    return favouritesListViewController;
}

#pragma mark - AKSitesListViewControllerDelegate Methods

- (void)sitesListViewController:(AKSitesListViewController *)sitesListViewController
                  didSelectSite:(AlfrescoSite *)site
          documentLibraryFolder:(AlfrescoFolder *)documentLibraryFolder
                          error:(NSError *)error
{
    UIViewController *viewController = [self folderOrDocumentPickingViewControllerWithRootFolder:documentLibraryFolder delegate:self session:self.session];
    [self.embeddedNavigationController pushViewController:viewController animated:YES];
}

#pragma mark - AKAlfrescoNodePickingListViewController Methods

- (void)nodePickingListViewController:(AKAlfrescoNodePickingListViewController *)nodePickingListViewController didSelectNodes:(NSArray *)selectedNodes;
{
    [self handleSelectionFromController:nodePickingListViewController selectedNodes:selectedNodes];
}

#pragma mark - AKNamingViewControllerDelegate Methods
#pragma mark Code used to handle creating content on the repo or moving to Local Files

- (void)namingViewController:(AKNamingViewController *)namingController didEnterName:(NSString *)name userInfo:(id)userInfo
{
    // If a node, then uploading to the repo, else, move to 
    if ([userInfo isKindOfClass:[AlfrescoNode class]])
    {
        BOOL access = [self.originalURL startAccessingSecurityScopedResource];
        
        if (access)
        {
            NSString *enteredFileName = [name stringByDeletingPathExtension];
            NSString *enteredExtension = name.pathExtension;
            
            NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
            NSError *error = nil;
            [fileCoordinator coordinateReadingItemAtURL:self.originalURL options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
                // Move the copy the file to the shared container
                NSString *pathExtension = (enteredExtension && enteredExtension.length > 0) ? enteredExtension : newURL.pathExtension;
                NSString *fileName = [enteredFileName stringByAppendingPathExtension:pathExtension];
                
                NSURL *outURL = [self.documentStorageURL URLByAppendingPathComponent:fileName];
                NSFileManager *fileManager = [[NSFileManager alloc] init];
                [fileManager copyItemAtURL:newURL toURL:outURL overwritingExistingFile:YES error:nil];
                
                // Show Progress HUD
                MBProgressHUD *progressHUD = [self progressHUDForView:namingController.view];
                [namingController.view addSubview:progressHUD];
                [progressHUD show:YES];
                
                // Initiate the upload
                AlfrescoDocumentFolderService *docService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
                AlfrescoFolder *uploadFolder = (AlfrescoFolder *)userInfo;
                AlfrescoContentFile *contentFile = [[AlfrescoContentFile alloc] initWithUrl:outURL];
                
                NSInputStream *inputStream = [NSInputStream inputStreamWithURL:outURL];
                AlfrescoContentStream *contentStream = [[AlfrescoContentStream alloc] initWithStream:inputStream mimeType:contentFile.mimeType length:contentFile.length];
                [docService createDocumentWithName:fileName inParentFolder:uploadFolder contentStream:contentStream properties:nil completionBlock:^(AlfrescoDocument *document, NSError *error) {
                    [progressHUD hide:YES];
                    if (error)
                    {
                        [self displayErrorAlertWithTitle:NSLocalizedString(@"Error", @"Error") message:error.localizedDescription error:error];
                    }
                    else
                    {
                        [self dismissGrantingAccessToURL:outURL];
                    }
                } progressBlock:^(unsigned long long bytesTransferred, unsigned long long bytesTotal) {
                    progressHUD.progress = (bytesTotal != 0) ? (float)bytesTransferred / (float)bytesTotal : 0;
                }];
            }];
            [self.originalURL stopAccessingSecurityScopedResource];
        }
    }
    else
    {
        BOOL access = [self.originalURL startAccessingSecurityScopedResource];
        
        if (access)
        {
            NSString *enteredFileName = [name stringByDeletingPathExtension];
            NSString *enteredExtension = name.pathExtension;
            NSString *pathExtension = (enteredExtension && enteredExtension.length > 0) ? enteredExtension : self.originalURL.pathExtension;
            NSString *fileName = [enteredFileName stringByAppendingPathExtension:pathExtension];
            
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            
            NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] init];
            __block NSError *error = nil;
            [fileCoordinator coordinateReadingItemAtURL:self.originalURL options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
                NSURL *completeDocumentStorageURL = [self.documentStorageURL URLByAppendingPathComponent:fileName];
                NSError *copyError = nil;
                [fileManager copyItemAtURL:newURL toURL:completeDocumentStorageURL overwritingExistingFile:YES error:&copyError];
                
                if (copyError)
                {
                    AlfrescoLogError(@"Unable to copy file from location: %@ to location: %@", newURL, completeDocumentStorageURL);
                }
                
                // copy to downloads
                NSString *fullDestinationPath = [[[AlfrescoFileManager sharedManager] downloadsContentFolderPath] stringByAppendingPathComponent:fileName];
                NSURL *downloadPath = [NSURL fileURLWithPath:fullDestinationPath];
                
                if ([fileManager fileExistsAtPath:fullDestinationPath])
                {
                    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"No") style:UIAlertActionStyleCancel handler:nil];
                    UIAlertAction *overwrite = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"Yes") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        NSError *copyError = nil;
                        [fileManager copyItemAtURL:completeDocumentStorageURL toURL:downloadPath overwritingExistingFile:YES error:&copyError];
                        
                        if (copyError)
                        {
                            AlfrescoLogError(@"Unable to copy from: %@ to: %@", completeDocumentStorageURL, downloadPath);
                        }
                        
                        [self dismissGrantingAccessToURL:completeDocumentStorageURL];
                    }];
                    
                    NSString *title = NSLocalizedString(@"document.picker.scope.overwrite.title", @"Overwrite Title");
                    NSString *message = NSLocalizedString(@"document.picker.scope.overwrite.message", @"Overwrite Message");
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addAction:cancel];
                    [alertController addAction:overwrite];
                    [self presentViewController:alertController animated:YES completion:nil];
                }
                else
                {
                    NSError *copyError = nil;
                    [fileManager copyItemAtURL:completeDocumentStorageURL toURL:downloadPath overwritingExistingFile:YES error:&copyError];
                    
                    if (copyError)
                    {
                        AlfrescoLogError(@"Unable to copy from: %@ to: %@", completeDocumentStorageURL, downloadPath);
                    }
                    
                    [self dismissGrantingAccessToURL:completeDocumentStorageURL];
                }
            }];
            
            [self.originalURL stopAccessingSecurityScopedResource];
        }
    }
}

#pragma mark - AKNetworkActivity Methods

- (void)controller:(UIViewController *)controller didStartRequest:(AlfrescoRequest *)request
{
    MBProgressHUD *spinner = [self spinningHUDForView:controller.view];
    [controller.view addSubview:spinner];
    [spinner show:YES];
}

- (void)controller:(UIViewController *)controller didCompleteRequest:(AlfrescoRequest *)request error:(NSError *)error
{
    for (UIView *subview in controller.view.subviews)
    {
        if ([subview isKindOfClass:[MBProgressHUD class]])
        {
            MBProgressHUD *hud = (MBProgressHUD *)subview;
            [hud hide:YES];
        }
    }
}

#pragma mark - AKLocalFilesViewControllerDelegate Methods

- (void)localFileViewController:(AKLocalFilesViewController *)localFileViewController didSelectFolderURL:(NSURL *)folderURL
{
    AKNamingViewController *namingController = [[AKNamingViewController alloc] initWithURL:nil delegate:self userInfo:folderURL];
    [self.embeddedNavigationController pushViewController:namingController animated:YES];
}

- (void)localFileViewController:(AKLocalFilesViewController *)localFileViewController didSelectDocumentURLPaths:(NSArray *)documentURLPaths
{
    // Currently only support one file, so get the first URL from the array
    NSURL *fileURL = documentURLPaths.firstObject;
    NSURL *outURL = [self.documentStorageURL URLByAppendingPathComponent:fileURL.path.lastPathComponent];
    
    if (self.documentPickerMode == UIDocumentPickerModeImport)
    {
        // Move the file into the document storage URL
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
        [coordinator coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForReplacing error:nil byAccessor:^(NSURL *newURL) {
            NSError *copyError = nil;
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            [fileManager copyItemAtURL:newURL toURL:outURL overwritingExistingFile:YES error:&copyError];
            
            if (copyError)
            {
                AlfrescoLogError(@"Unable to copy from: %@ to: %@", newURL, outURL);
            }
        }];
        
        [self dismissGrantingAccessToURL:outURL];
    }
    else if (self.documentPickerMode == UIDocumentPickerModeOpen)
    {
        NSArray *fileURLs = [self.queueStore.queue valueForKey:@"fileURL"];
        
        if (![fileURLs containsObject:outURL])
        {
            FileMetadata *metadata = [[FileMetadata alloc] initWithAccountIdentififer:self.account.identifier repositoryNode:nil fileURL:outURL sourceLocation:FileMetadataSaveLocationLocalFiles];
            [self.queueStore addObjectToQueue:metadata];
            [self.queueStore saveQueue];
        }
        
        [self dismissGrantingAccessToURL:outURL];
    }
}

#pragma mark - AKFavoritesListViewControllerDelegate Methods

- (void)favoritesListViewController:(AKFavoritesListViewController *)favoritesListViewController didSelectNodes:(NSArray *)selectedNodes
{
    [self handleSelectionFromController:favoritesListViewController selectedNodes:selectedNodes];
}

@end