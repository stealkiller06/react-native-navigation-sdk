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

#import "NavModule.h"
#import "NavEventDispatcher.h"
#import "NavViewModule.h"
#import "ObjectTranslationUtil.h"

@implementation NavModule {
    GMSNavigationSession *_session;
    NSMutableArray<GMSNavigationMutableWaypoint *> *_destinations;
    NSDictionary *_tosParams;
}

@synthesize enableUpdateInfo = _enableUpdateInfo;
static NavEventDispatcher *_eventDispatcher;

// Static instance of the NavViewModule to allow access from another modules.
static NavModule *sharedInstance = nil;

RCT_EXPORT_MODULE(NavModule);


+ (id)allocWithZone:(NSZone *)zone {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [super allocWithZone:zone];
    });
    return sharedInstance;
}

// Method to get the shared instance
+ (instancetype)sharedInstance {
    return sharedInstance;
}

- (BOOL)hasSession {
    return _session != nil;
}

- (GMSNavigationSession *)getSession {
    return _session;
}

- (GMSNavigator *)getNavigator {
    if (self->_session == nil) {
        @throw [NSException
                exceptionWithName:@"GoogleMapsNavigationSessionManagerError"
                reason:@"Navigation session not initialized"
                userInfo:nil];
    }
    
    GMSNavigator *navigator = self->_session.navigator;
    if (navigator == nil) {
        @throw [NSException
                exceptionWithName:@"GoogleMapsNavigationSessionManagerError"
                reason:@"Terms not accepted"
                userInfo:nil];
    }
    
    return navigator;
}

- (void)initializeSession {
    // TODO(jokerttu): init mapviews on navigation initialization
    // [_mapView.settings setCompassButton:YES];
    // [self setMyLocationEnabled:YES];
    // [_mapView.settings setMyLocationButton:YES];
    
    // [_mapView.navigationUIDelegate self];
    //  _mapView.navigationEnabled = YES;
    
    // Try to create a navigation session.
    
    if (self->_session == nil && self->_session.navigator == nil) {
        GMSNavigationSession *session =
        [GMSNavigationServices createNavigationSession];
        if (session == nil) {
            // According to the API documentation, the only reason a nil session is
            // ever returned is due to terms and conditions not having been accepted
            // yet.
            //
            // At this point, this should not happen due to the earlier check.
            @throw [NSException
                    exceptionWithName:@"GoogleMapsNavigationSessionManagerError"
                    reason:@"Terms not accepted"
                    userInfo:nil];
        }
        self->_session = session;
    }
    
    _session.started = YES;
    
    if (self->_session.navigator) {
        [self->_session.navigator addListener:self];
        self->_session.navigator.stopGuidanceAtArrival = NO;
        self->_session.navigator.timeUpdateThreshold = DBL_MAX;
        self->_session.navigator.distanceUpdateThreshold = CLLocationDistanceMax;
    }
    
    [self->_session.roadSnappedLocationProvider addListener:self];
    
    NavViewModule *navViewModule = [NavViewModule sharedInstance];
    [navViewModule attachViewsToNavigationSession:_session];
    
    // TODO(jokerttu): init mapviews on navigation initialization
    //_mapView.cameraMode = GMSNavigationCameraModeFollowing;
    //[_mapView setFollowingPerspective:GMSNavigationCameraPerspectiveTilted];
    
    [self onNavigationReady];
}

- (void)showTermsAndConditionsDialog {
    BOOL showAwareness = _tosParams[@"showOnlyDisclaimer"] != nil &&
    [_tosParams[@"showOnlyDisclaimer"] boolValue];
    
    [GMSNavigationServices
     setShouldOnlyShowDriverAwarenesssDisclaimer:showAwareness];
    
    NSString *companyName = [_tosParams valueForKey:@"companyName"];
    NSString *titleHead = [_tosParams valueForKey:@"title"];
    
    [GMSNavigationServices
     showTermsAndConditionsDialogIfNeededWithTitle:titleHead
     companyName:companyName
     callback:^(BOOL termsAccepted) {
        if (termsAccepted) {
            [self initializeSession];
        } else {
            [self onNavigationInitError:@2];
        }
    }];
}

RCT_EXPORT_METHOD(initializeNavigator : (NSDictionary *)options) {
    dispatch_async(dispatch_get_main_queue(), ^{
        _tosParams = options;
        [self showTermsAndConditionsDialog];
    });
}

RCT_EXPORT_METHOD(cleanup) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_session == nil) {
            @throw [NSException
                    exceptionWithName:@"GoogleMapsNavigationSessionManagerError"
                    reason:@"Navigation session not initialized"
                    userInfo:nil];
        }
        
        if (self->_session.locationSimulator != nil) {
            [self->_session.locationSimulator stopSimulation];
        }
        
        if (self->_session.navigator != nil) {
            [self->_session.navigator clearDestinations];
            self->_session.navigator.guidanceActive = NO;
            self->_session.navigator.sendsBackgroundNotifications = NO;
        }
        
        if (self->_session.roadSnappedLocationProvider != nil) {
            [self->_session.roadSnappedLocationProvider removeListener:self];
        }
        
        self->_session.started = NO;
        self->_session = nil;
    });
}

RCT_EXPORT_METHOD(setTurnByTurnLoggingEnabled : (BOOL)isEnabled) {
    self.enableUpdateInfo = isEnabled;
}

RCT_EXPORT_METHOD(getCurrentTimeAndDistance
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self getNavigator]) {
            reject(@"navigator_not_initialized", @"Navigator not initialized", nil);
            return;
        }
        
        if (![self getNavigator].currentRouteLeg) {
            reject(@"route_not_available", @"No current route available", nil);
            return;
        }
        
        GMSNavigationDelayCategory severity =
        [self getNavigator].delayCategoryToNextDestination;
        NSTimeInterval time = [self getNavigator].timeToNextDestination;
        CLLocationDistance distance = [self getNavigator].distanceToNextDestination;
        
        resolve(@{
            @"delaySeverity" : @(severity),
            @"meters" : @(distance),
            @"seconds" : @(time)
        });
    });
}

RCT_EXPORT_METHOD(setAudioGuidanceType : (nonnull NSNumber *)index) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self getNavigator]) {
            // TODO: throw error.
            return;
        }
        if ([index isEqual:@0]) {
            [[self getNavigator] setVoiceGuidance:GMSNavigationVoiceGuidanceSilent];
        } else if ([index isEqual:@1]) {
            [[self getNavigator]
             setVoiceGuidance:GMSNavigationVoiceGuidanceAlertsOnly];
        } else {
            [[self getNavigator]
             setVoiceGuidance:GMSNavigationVoiceGuidanceAlertsAndGuidance];
        }
    });
}

RCT_EXPORT_METHOD(startGuidance) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_destinations != NULL) {
            [self getNavigator].guidanceActive = YES;
            [self onStartGuidance];
            [self getNavigator].sendsBackgroundNotifications = YES;
        }
    });
}

RCT_EXPORT_METHOD(stopGuidance) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self getNavigator].guidanceActive = false;
    });
}

RCT_EXPORT_METHOD(simulateLocationsAlongExistingRoute
                  : (nonnull NSNumber *)speedMultiplier) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_destinations != nil && self->_session != nil) {
            [self->_session.locationSimulator
             setSpeedMultiplier:[speedMultiplier floatValue]];
            [self->_session.locationSimulator simulateLocationsAlongExistingRoute];
        }
    });
}

RCT_EXPORT_METHOD(stopLocationSimulation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_session != nil) {
            [self->_session.locationSimulator stopSimulation];
        }
    });
}

RCT_EXPORT_METHOD(clearDestinations) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self getNavigator] clearDestinations];
        self->_destinations = NULL;
    });
}

RCT_EXPORT_METHOD(continueToNextDestination) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self getNavigator] continueToNextDestination];
    });
}

RCT_EXPORT_METHOD(setDestination
                  : (nonnull NSDictionary *)waypoint routingOptions
                  : (NSDictionary *)routingOptions) {
    NSArray *waypoints = @[ waypoint ];
    [self setDestinations:waypoints routingOptions:routingOptions];
}

RCT_EXPORT_METHOD(setDestinations
                  : (nonnull NSArray *)waypoints routingOptions
                  : (NSDictionary *)routingOptions) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_destinations = [[NSMutableArray alloc] init];
        
        for (NSDictionary *wp in waypoints) {
            GMSNavigationMutableWaypoint *w;
            
            NSString *placeId = wp[@"placeId"];
            
            if (placeId && ![placeId isEqual:@""]) {
                w = [[GMSNavigationMutableWaypoint alloc] initWithPlaceID:placeId
                                                                    title:wp[@"title"]];
            } else if (wp[@"position"]) {
                w = [[GMSNavigationMutableWaypoint alloc]
                     initWithLocation:[ObjectTranslationUtil
                                       getLocationCoordinateFrom:wp[@"position"]]
                     title:wp[@"title"]];
            } else {
                // The validation will be done on the client, so just ignore this
                // waypoint here.
                continue;
            }
            
            if (wp[@"preferSameSideOfRoad"] != nil) {
                w.preferSameSideOfRoad = [wp[@"preferSameSideOfRoad"] boolValue];
            }
            
            if (wp[@"vehicleStopover"] != nil) {
                w.vehicleStopover = [wp[@"vehicleStopover"] boolValue];
            }
            
            if (wp[@"preferredHeading"] != nil) {
                w.preferredHeading = [wp[@"preferredHeading"] intValue];
            }
            
            [strongSelf->_destinations addObject:w];
        }
        
        if (routingOptions != NULL) {
            [strongSelf configureNavigator:routingOptions];
            [[strongSelf getNavigator]
             setDestinations:strongSelf->_destinations
             routingOptions:[NavModule getRoutingOptions:routingOptions]
             callback:^(GMSRouteStatus routeStatus) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf)
                    return;
                [strongSelf onRouteStatusResult:routeStatus];
            }];
        } else {
            [[strongSelf getNavigator]
             setDestinations:strongSelf->_destinations
             callback:^(GMSRouteStatus routeStatus) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf)
                    return;
                [strongSelf onRouteStatusResult:routeStatus];
            }];
        }
    });
}

+ (GMSNavigationRoutingOptions *)getRoutingOptions:(NSDictionary *)options {
    GMSNavigationMutableRoutingOptions *routingOptions =
    [[GMSNavigationMutableRoutingOptions alloc]
     initWithRoutingStrategy:(GMSNavigationRoutingStrategy)
     [options[@"routingStrategy"] intValue]];
    
    [routingOptions setAlternateRoutesStrategy:
     (GMSNavigationAlternateRoutesStrategy)
     [options[@"alternateRoutesStrategy"] intValue]];
    
    return routingOptions;
}

- (void)configureNavigator:(NSDictionary *)routingOptions {
    // TODO(jokerttu): pass travelmode to the views
    // if (routingOptions[@"travelMode"] != nil) {
    //  [_mapView
    //  setTravelMode:(GMSNavigationTravelMode)[routingOptions[@"travelMode"]
    //  intValue]];
    //}
    
    if (routingOptions[@"avoidTolls"] != nil) {
        [[self getNavigator]
         setAvoidsTolls:[routingOptions[@"avoidTolls"] boolValue]];
    }
    
    if (routingOptions[@"avoidFerries"] != nil) {
        [[self getNavigator]
         setAvoidsTolls:[routingOptions[@"avoidFerries"] boolValue]];
    }
    
    if (routingOptions[@"avoidHighways"] != nil) {
        [[self getNavigator]
         setAvoidsTolls:[routingOptions[@"avoidHighways"] boolValue]];
    }
}

RCT_EXPORT_METHOD(setBackgroundLocationUpdatesEnabled : (BOOL)isEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        _session.roadSnappedLocationProvider.allowsBackgroundLocationUpdates =
        isEnabled;
    });
}

RCT_EXPORT_METHOD(getCurrentRouteSegment
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self getNavigator]) {
            reject(@"navigator_not_initialized", @"Navigator not initialized", nil);
            return;
        }
        
        GMSRouteLeg *currentSegment = [self getNavigator].currentRouteLeg;
        if (!currentSegment) {
            reject(@"route_not_available", @"No current route available", nil);
            return;
        }
        
        resolve(@{
            @"destinationLatLng" : [ObjectTranslationUtil
                                    transformCoordinateToDictionary:currentSegment.destinationCoordinate],
            @"destinationWaypoint" : [ObjectTranslationUtil
                                      transformNavigationWaypointToDictionary:currentSegment
                .destinationWaypoint],
            @"segmentLatLngList" :
                [ObjectTranslationUtil transformGMSPathToArray:currentSegment.path]
        });
    });
}

RCT_EXPORT_METHOD(getRouteSegments
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self getNavigator]) {
            reject(@"navigator_not_initialized", @"Navigator not initialized", nil);
            return;
        }
        
        NSArray<GMSRouteLeg *> *routeSegmentList = [self getNavigator].routeLegs;
        if (!routeSegmentList) {
            reject(@"route_not_available", @"No current route available", nil);
            return;
        }
        
        NSMutableArray *arr = [[NSMutableArray alloc] init];
        
        for (int i = 0; i < routeSegmentList.count; i++) {
            [arr
             addObject:[ObjectTranslationUtil
                        transformRouteSegmentToDictionary:routeSegmentList[i]]];
        }
        
        resolve(arr);
    });
}

RCT_EXPORT_METHOD(getTraveledPath
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        GMSPath *traveledPath = [self getNavigator].traveledPath;
        
        if (traveledPath != nil) {
            resolve([ObjectTranslationUtil transformGMSPathToArray:traveledPath]);
        } else {
            resolve(nil);
        }
    });
}

RCT_EXPORT_METHOD(setSpeedAlertOptions : (NSDictionary *)thresholds) {
    dispatch_async(dispatch_get_main_queue(), ^{
        double minor = [thresholds[@"minorSpeedAlertPercentThreshold"] doubleValue];
        double major = [thresholds[@"majorSpeedAlertPercentThreshold"] doubleValue];
        double severity =
        [thresholds[@"severityUpgradeDurationSeconds"] doubleValue];
        
        CGFloat minorSpeedAlertThresholdPercentage = minor;
        CGFloat majorSpeedAlertThresholdPercentage = major;
        NSTimeInterval severityUpgradeDurationSeconds = severity;
        
        GMSNavigationMutableSpeedAlertOptions *mutableSpeedAlertOptions =
        [[GMSNavigationMutableSpeedAlertOptions alloc] init];
        
        [mutableSpeedAlertOptions
         setSpeedAlertThresholdPercentage:minorSpeedAlertThresholdPercentage
         forSpeedAlertSeverity:GMSNavigationSpeedAlertSeverityMinor];
        [mutableSpeedAlertOptions
         setSpeedAlertThresholdPercentage:majorSpeedAlertThresholdPercentage
         forSpeedAlertSeverity:GMSNavigationSpeedAlertSeverityMajor];
        [mutableSpeedAlertOptions
         setSeverityUpgradeDurationSeconds:severityUpgradeDurationSeconds];
        
        // Set SpeedAlertOptions to Navigator
        [self getNavigator].speedAlertOptions = mutableSpeedAlertOptions;
    });
}

RCT_EXPORT_METHOD(simulateLocation : (NSDictionary *)coordinates) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_session != nil) {
            [self->_session.locationSimulator
             simulateLocationAtCoordinate:
                 [ObjectTranslationUtil
                  getLocationCoordinateFrom:coordinates[@"location"]]];
        }
    });
}

RCT_EXPORT_METHOD(pauseLocationSimulation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_session != nil) {
            self->_session.locationSimulator.paused = YES;
        }
    });
}

RCT_EXPORT_METHOD(resumeLocationSimulation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_session != nil) {
            self->_session.locationSimulator.paused = NO;
        }
    });
}

RCT_EXPORT_METHOD(areTermsAccepted
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (GMSNavigationServices.areTermsAndConditionsAccepted == NO) {
            resolve(@"false");
        } else {
            resolve(@"true");
        }
    });
}

RCT_EXPORT_METHOD(getNavSDKVersion
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        resolve(GMSNavigationServices.navSDKVersion);
    });
}

RCT_EXPORT_METHOD(setAbnormalTerminatingReportingEnabled : (BOOL)isEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [GMSNavigationServices setAbnormalTerminationReportingEnabled:isEnabled];
    });
}

RCT_EXPORT_METHOD(startUpdatingLocation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_session.roadSnappedLocationProvider startUpdatingLocation];
    });
}

RCT_EXPORT_METHOD(stopUpdatingLocation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_session.roadSnappedLocationProvider stopUpdatingLocation];
    });
}

/* TODO: Implement
 - (void)removeNavigationListeners {
 [_mapView.navigator removeListener:self];
 }
 */

- (void)sendCommandToReactNative:(NSString *)command {
    if (_eventDispatcher != NULL) {
        [_eventDispatcher sendEventName:command
                                   body:@{
            @"args" : @[],
        }];
    }
}

- (void)sendCommandToReactNative:(NSString *)command args:(NSObject *)args {
    if (_eventDispatcher != NULL) {
        [_eventDispatcher sendEventName:command body:args];
    }
}

#pragma mark - GMSNavigatorListener
// Listener for continuous location updates.
- (void)locationProvider:(GMSRoadSnappedLocationProvider *)locationProvider
       didUpdateLocation:(CLLocation *)location {
    [self onLocationChanged:[ObjectTranslationUtil
                             transformCLLocationToDictionary:location]];
}

// Listener to handle arrival events.
- (void)navigator:(GMSNavigator *)navigator
didArriveAtWaypoint:(GMSNavigationWaypoint *)waypoint {
    NSMutableDictionary *eventMap = [[NSMutableDictionary alloc] init];
    
    eventMap[@"waypoint"] =
    [ObjectTranslationUtil transformNavigationWaypointToDictionary:waypoint];
    eventMap[@"isFinalDestination"] =
    @(navigator.routeLegs != nil && navigator.routeLegs.count == 1);
    
    [self onArrival:eventMap];
}

// Listener for route change events.
- (void)navigatorDidChangeRoute:(GMSNavigator *)navigator {
    [self onRouteChanged];
}

// Listener for time to next destination.
- (void)navigator:(GMSNavigator *)navigator
didUpdateRemainingTime:(NSTimeInterval)time {
    [self onRemainingTimeOrDistanceChanged];
}

// Listener for distance to next destination.
- (void)navigator:(GMSNavigator *)navigator
didUpdateRemainingDistance:(CLLocationDistance)distance {
    [self onRemainingTimeOrDistanceChanged];
}

- (void)navigator:(GMSNavigator *)navigator
 didUpdateNavInfo:(GMSNavigationNavInfo *)navInfo {
    if (self.enableUpdateInfo == TRUE &&
        navInfo.navState == GMSNavigationNavStateEnroute) {
        [self onTurnByTurn:navInfo
distanceToNextDestinationMeters:[self getNavigator]
         .distanceToNextDestination
timeToNextDestinationSeconds:[self getNavigator]
         .timeToNextDestination];
    }
}

#pragma mark - INavigationCallback
- (void)onLocationChanged:(NSDictionary *)mappedLocation {
    [self sendCommandToReactNative:@"onLocationChanged" args:mappedLocation];
}

- (void)onArrival:(NSDictionary *)eventMap {
    [self sendCommandToReactNative:@"onArrival" args:eventMap];
}

- (void)onNavigationReady {
    // Update view settings after the navigation is ended
    // TODO(jokerttu(: update views
    /*
     @synchronized(_viewControllers) {
     [_viewControllers
     enumerateKeysAndObjectsUsingBlock:^(
     NSNumber *key, NavViewController *viewController, BOOL *stop) {
     [viewController setStylingOptions:_stylingOptions];
     }];
     }
     */
    
    [self sendCommandToReactNative:@"onNavigationReady"];
}

- (void)onNavigationInitError:(NSNumber *)errorCode {
    [self sendCommandToReactNative:@"onNavigationInitError" args:errorCode];
}

- (void)onRemainingTimeOrDistanceChanged {
    [self sendCommandToReactNative:@"onRemainingTimeOrDistanceChanged"];
}

- (void)onRouteChanged {
    [self sendCommandToReactNative:@"onRouteChanged"];
}

- (void)onReroutingRequestedByOffRoute {
    [self sendCommandToReactNative:@"onReroutingRequestedByOffRoute"];
}

- (void)onStartGuidance {
    [self sendCommandToReactNative:@"onStartGuidance"];
}

- (void)onRouteStatusResult:(GMSRouteStatus)routeStatus {
    NSString *status = @"";
    switch (routeStatus) {
        case GMSRouteStatusOK:
            status = @"OK";
            break;
        case GMSRouteStatusNetworkError:
            status = @"NETWORK_ERROR";
            break;
        case GMSRouteStatusNoRouteFound:
            status = @"NO_ROUTE_FOUND";
            break;
        case GMSRouteStatusQuotaExceeded:
            status = @"QUOTA_CHECK_FAILED";
            break;
        case GMSRouteStatusCanceled:
            status = @"ROUTE_CANCELED";
            break;
        case GMSRouteStatusLocationUnavailable:
            status = @"LOCATION_DISABLED";
            break;
        case GMSRouteStatusNoWaypointsError:
            status = @"WAYPOINT_ERROR";
            break;
        case GMSRouteStatusWaypointError:
            status = @"WAYPOINT_ERROR";
            break;
        default:
            status = @"";
            break;
    }
    [self sendCommandToReactNative:@"onRouteStatusResult" args:status];
}

- (void)onTurnByTurn:(nonnull GMSNavigationNavInfo *)navInfo {
    [self onTurnByTurn:navInfo
distanceToNextDestinationMeters:0
timeToNextDestinationSeconds:0];
}

- (void)onTurnByTurn:(GMSNavigationNavInfo *)navInfo
distanceToNextDestinationMeters:(double)distanceToNextDestinationMeters
timeToNextDestinationSeconds:(double)timeToNextDestinationSeconds {
    NSMutableDictionary *obj = [[NSMutableDictionary alloc] init];
    
    [obj setValue:[NSNumber numberWithLong:navInfo.navState] forKey:@"navState"];
    [obj setValue:[NSNumber numberWithBool:navInfo.routeChanged]
           forKey:@"routeChanged"];
    if (navInfo.distanceToCurrentStepMeters) {
        [obj setValue:[NSNumber numberWithLong:navInfo.distanceToCurrentStepMeters]
               forKey:@"distanceToCurrentStepMeters"];
    }
    
    if (navInfo.distanceToFinalDestinationMeters) {
        [obj setValue:[NSNumber
                       numberWithLong:navInfo.distanceToFinalDestinationMeters]
               forKey:@"distanceToFinalDestinationMeters"];
    }
    if (navInfo.timeToCurrentStepSeconds) {
        [obj setValue:[NSNumber numberWithLong:navInfo.timeToCurrentStepSeconds]
               forKey:@"timeToCurrentStepSeconds"];
    }
    
    if (distanceToNextDestinationMeters) {
        [obj setValue:[NSNumber numberWithLong:distanceToNextDestinationMeters]
               forKey:@"distanceToNextDestinationMeters"];
    }
    
    if (timeToNextDestinationSeconds) {
        [obj setValue:[NSNumber numberWithLong:timeToNextDestinationSeconds]
               forKey:@"timeToNextDestinationSeconds"];
    }
    
    if (navInfo.timeToFinalDestinationSeconds) {
        [obj
         setValue:[NSNumber numberWithLong:navInfo.timeToFinalDestinationSeconds]
         forKey:@"timeToFinalDestinationSeconds"];
    }
    
    if (navInfo.currentStep != NULL) {
        [obj setObject:[self getStepInfo:navInfo.currentStep]
                forKey:@"currentStep"];
    }
    
    NSMutableArray *steps = [[NSMutableArray alloc] init];
    
    if (navInfo.remainingSteps != NULL) {
        for (GMSNavigationStepInfo *step in navInfo.remainingSteps) {
            if (step != NULL) {
                [steps addObject:[self getStepInfo:step]];
            }
        }
    }
    
    [obj setObject:steps forKey:@"getRemainingSteps"];
    
    NSMutableArray *params = [NSMutableArray array];
    [params addObject:obj];
    [_eventDispatcher sendEventName:@"onTurnByTurn"
                               body:@{
        @"args" : params,
    }];
}

- (NSDictionary *)getStepInfo:(GMSNavigationStepInfo *)stepInfo {
    NSMutableDictionary *obj = [[NSMutableDictionary alloc] init];
    
    [obj setValue:[NSNumber numberWithInteger:stepInfo.distanceFromPrevStepMeters]
           forKey:@"distanceFromPrevStepMeters"];
    [obj setValue:[NSNumber numberWithInteger:stepInfo.timeFromPrevStepSeconds]
           forKey:@"timeFromPrevStepSeconds"];
    [obj setValue:[NSNumber numberWithInteger:stepInfo.drivingSide]
           forKey:@"drivingSide"];
    [obj setValue:[NSNumber numberWithInteger:stepInfo.stepNumber]
           forKey:@"stepNumber"];
    [obj setValue:[NSNumber numberWithInteger:stepInfo.maneuver]
           forKey:@"maneuver"];
    [obj setValue:stepInfo.exitNumber forKey:@"exitNumber"];
    [obj setValue:stepInfo.fullRoadName forKey:@"fullRoadName"];
    [obj setValue:stepInfo.fullInstructionText forKey:@"instruction"];
    
    return obj;
}

@end