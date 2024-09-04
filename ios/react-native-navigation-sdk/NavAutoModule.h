/**
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#import <React/RCTBridgeModule.h>
#import "NavViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NavAutoModule : NSObject <RCTBridgeModule>
@property (nonatomic, strong) NavViewController *viewController;

typedef void (^NavAutoModuleReadyCallback)(void);

- (void)registerViewController:(NavViewController *)vc;
+ (void)registerNavAutoModuleReadyCallback:(NavAutoModuleReadyCallback)callback;
+ (void)unregisterNavAutoModuleReadyCallback;

// Class method to access the singleton instance
+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END