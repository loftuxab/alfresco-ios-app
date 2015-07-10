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

#import "BaseFileFolderCollectionViewController.h"
#import "UploadFormViewController.h"
#import "DownloadsViewController.h"
#import "MultiSelectActionsToolbar.h"
#import "CollectionViewProtocols.h"
#import "BaseCollectionViewFlowLayout.h"

@class AlfrescoFolder;
@class AlfrescoPermissions;
@protocol AlfrescoSession;

@interface FileFolderCollectionViewController : BaseFileFolderCollectionViewController

/**
 Providing nil to the folder parameter will result in the root folder (Company Home) being displayed.
 
 @param folder - the content of this folder will be displayed. Providing nil will result in Company Home being displayed.
 @param displayName - the name that will be visible to the user when at the root of the navigation stack.
 @param session - the user' session
 */
- (instancetype)initWithFolder:(AlfrescoFolder *)folder session:(id<AlfrescoSession>)session;
- (instancetype)initWithFolder:(AlfrescoFolder *)folder folderDisplayName:(NSString *)displayName session:(id<AlfrescoSession>)session;

/**
 Use the permissions initialiser to avoid the visual refreshing of the navigationItem barbuttons. Failure to set these will result in the
 permissions being retrieved once the controller's view is displayed.
 
 @param folder - the content of this folder will be displayed. Providing nil will result in Company Home being displayed.
 @param permissions - the permissions of the folder
 @param displayName - the name that will be visible to the user when at the root of the navigation stack.
 @param session - the user' session
 */
- (instancetype)initWithFolder:(AlfrescoFolder *)folder folderPermissions:(AlfrescoPermissions *)permissions session:(id<AlfrescoSession>)session;
- (instancetype)initWithFolder:(AlfrescoFolder *)folder folderPermissions:(AlfrescoPermissions *)permissions folderDisplayName:(NSString *)displayName session:(id<AlfrescoSession>)session;

/**
 Use the site short name initialiser to display the document library for the given site. Failure to provide a site short name will result in a company home controller.
 
 @param siteShortName - the site short name to which the document library folder should be shown. Providing nil will result in Company Home being displayed.
 @param permissions - the permissions of the site
 @param displayName - the name that will be visible to the user when at the root of the navigation stack.
 @param session - the users session
 */
- (instancetype)initWithSiteShortname:(NSString *)siteShortName sitePermissions:(AlfrescoPermissions *)permissions siteDisplayName:(NSString *)displayName session:(id<AlfrescoSession>)session;

/**
 Use the folder path initialiser to display the contents of a folder node at a given path. Failure to provide a folder path will result in a company home controller.
 
 @param folderPath - the folder path for which the contents should be shown. Providing nil will result in Company Home being displayed.
 @param permissions - the folder's permissions
 @param displayName - the name that will be visible to the user when at the root of the navigation stack.
 @param session - the users session
 */
- (instancetype)initWithFolderPath:(NSString *)folderPath folderPermissions:(AlfrescoPermissions *)permissions folderDisplayName:(NSString *)displayName session:(id<AlfrescoSession>)session;

/**
 Convinece method used to help initialise the internal state of the controller once initialised.
 
 @param folder - the content of this folder will be displayed. Providing nil will result in Company Home being displayed.
 @param permissions - the permissions of the folder
 @param displayName - the name that will be visible to the user when at the root of the navigation stack.
 @param session - the user' session
 */
- (void)setupWithFolder:(AlfrescoFolder *)folder folderPermissions:(AlfrescoPermissions *)permissions folderDisplayName:(NSString *)displayName session:(id<AlfrescoSession>)session;

@end
