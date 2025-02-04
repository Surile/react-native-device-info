//
//  RNDeviceInfo.m
//  Learnium
//
//  Created by Rebecca Hughes on 03/08/2015.
//  Copyright © 2015 Learnium Limited. All rights reserved.
//

#include <ifaddrs.h>
#include <arpa/inet.h>
#import <mach/mach.h>
#import <mach-o/arch.h>
#import <CoreLocation/CoreLocation.h>
#import <React/RCTUtils.h>
#import "RNDeviceInfo.h"
#import "DeviceUID.h"
#import <DeviceCheck/DeviceCheck.h>
#import "EnvironmentUtil.h"

#if !(TARGET_OS_TV)
#import <WebKit/WebKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#endif

typedef NS_ENUM(NSInteger, DeviceType) {
    DeviceTypeHandset,
    DeviceTypeTablet,
    DeviceTypeTv,
    DeviceTypeDesktop,
    DeviceTypeHeadset,
    DeviceTypeUnknown
};

#define DeviceTypeValues [NSArray arrayWithObjects: @"Handset", @"Tablet", @"Tv", @"Desktop", @"Headset", @"unknown", nil]

#if (!(TARGET_OS_TV || TARGET_OS_VISION))
@import CoreTelephony;
#endif

@import Darwin.sys.sysctl;

@implementation RNDeviceInfo
{
    bool hasListeners;
}

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup
{
   return NO;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"RNDeviceInfo_batteryLevelDidChange", @"RNDeviceInfo_batteryLevelIsLow", @"RNDeviceInfo_powerStateDidChange", @"RNDeviceInfo_headphoneConnectionDidChange", @"RNDeviceInfo_headphoneWiredConnectionDidChange", @"RNDeviceInfo_headphoneBluetoothConnectionDidChange", @"RNDeviceInfo_brightnessDidChange"];
}

- (NSDictionary *)constantsToExport {
    return @{
         @"deviceId": [self getDeviceId],
         @"bundleId": [self getBundleId],
         @"systemName": [self getSystemName],
         @"systemVersion": [self getSystemVersion],
         @"appVersion": [self getAppVersion],
         @"buildNumber": [self getBuildNumber],
         @"isTablet": @([self isTablet]),
         @"appName": [self getAppName],
         @"brand": @"Apple",
         @"model": [self getModel],
         @"deviceType": [self getDeviceTypeName],
         @"isDisplayZoomed": @([self isDisplayZoomed]),
     };
}

- (id)init
{
    if ((self = [super init])) {
#if !TARGET_OS_TV
        _lowBatteryThreshold = 0.20;
        [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(batteryLevelDidChange:)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(powerStateDidChange:)
                                                     name:UIDeviceBatteryStateDidChangeNotification
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(powerStateDidChange:)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(headphoneConnectionDidChange:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object: [AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(headphoneWiredConnectionDidChange:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object: [AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(headphoneBluetoothConnectionDidChange:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object: [AVAudioSession sharedInstance]];
        #if !TARGET_OS_VISION
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(brightnessDidChange:)
                                                     name:UIScreenBrightnessDidChangeNotification
                                                   object: nil];
        #endif
#endif
    }

    return self;
}

- (void)startObserving {
    hasListeners = YES;
}

- (void)stopObserving {
    hasListeners = NO;
}

- (DeviceType) getDeviceType
{
    switch ([[UIDevice currentDevice] userInterfaceIdiom]) {
        case UIUserInterfaceIdiomPhone: return DeviceTypeHandset;
        case UIUserInterfaceIdiomPad:
            if (TARGET_OS_MACCATALYST) {
                return DeviceTypeDesktop;
            }
            if (@available(iOS 14.0, *)) {
                if ([NSProcessInfo processInfo].isiOSAppOnMac) {
                    return DeviceTypeDesktop;
                }
            }
            return DeviceTypeTablet;
        case UIUserInterfaceIdiomTV: return DeviceTypeTv;
        case UIUserInterfaceIdiomMac: return DeviceTypeDesktop;
    #if TARGET_OS_VISION
        case UIUserInterfaceIdiomVision: return DeviceTypeHeadset;
    #endif
        default: return DeviceTypeUnknown;
    }
}

- (NSDictionary *) getStorageDictionary {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: nil];
}

- (NSString *) getSystemName {
    UIDevice *currentDevice = [UIDevice currentDevice];
    return currentDevice.systemName;
}

- (NSString *) getSystemVersion {
    UIDevice *currentDevice = [UIDevice currentDevice];
    return currentDevice.systemVersion;
}

- (NSString *) getDeviceName {
    UIDevice *currentDevice = [UIDevice currentDevice];
    return currentDevice.name;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getDeviceNameSync) {
    return self.getDeviceName;
}

RCT_EXPORT_METHOD(getDeviceName:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getDeviceName);
}

- (BOOL) isDisplayZoomed {
    #if !TARGET_OS_VISION
        return [UIScreen mainScreen].scale < [UIScreen mainScreen].nativeScale;
    #else
        return NO;
    #endif
}

- (NSString *) getAppName {
    NSString *displayName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    return displayName ? displayName : bundleName;
}

- (NSString *) getBundleId {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
}

- (NSString *) getAppVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

- (NSString *) getBuildNumber {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (NSDictionary *) getDeviceNamesByCode {
    return @{
        @"iPhone1,1": @"iPhone", // (Original)
        @"iPhone1,2": @"iPhone 3G", // (3G)
        @"iPhone2,1": @"iPhone 3GS", // (3GS)
        @"iPhone3,1": @"iPhone 4", // (GSM)
        @"iPhone3,2": @"iPhone 4", // iPhone 4
        @"iPhone3,3": @"iPhone 4", // (CDMA/Verizon/Sprint)
        @"iPhone4,1": @"iPhone 4S", //
        @"iPhone5,1": @"iPhone 5", // (model A1428, AT&T/Canada)
        @"iPhone5,2": @"iPhone 5", // (model A1429, everything else)
        @"iPhone5,3": @"iPhone 5c", // (model A1456, A1532 | GSM)
        @"iPhone5,4": @"iPhone 5c", // (model A1507, A1516, A1526 (China), A1529 | Global)
        @"iPhone6,1": @"iPhone 5s", // (model A1433, A1533 | GSM)
        @"iPhone6,2": @"iPhone 5s", // (model A1457, A1518, A1528 (China), A1530 | Global)
        @"iPhone7,1": @"iPhone 6 Plus", //
        @"iPhone7,2": @"iPhone 6", //
        @"iPhone8,1": @"iPhone 6s", //
        @"iPhone8,2": @"iPhone 6s Plus", //
        @"iPhone8,4": @"iPhone SE", //
        @"iPhone9,1": @"iPhone 7", // (model A1660 | CDMA)
        @"iPhone9,2": @"iPhone 7 Plus", // (model A1661 | CDMA)
        @"iPhone9,3": @"iPhone 7", // (model A1778 | Global)
        @"iPhone9,4": @"iPhone 7 Plus", // (model A1784 | Global)
        @"iPhone10,1": @"iPhone 8", // (model A1863, A1906, A1907)
        @"iPhone10,2": @"iPhone 8 Plus", // (model A1864, A1898, A1899)
        @"iPhone10,3": @"iPhone X", // (model A1865, A1902)
        @"iPhone10,4": @"iPhone 8", // (model A1905)
        @"iPhone10,5": @"iPhone 8 Plus", // (model A1897)
        @"iPhone10,6": @"iPhone X", // (model A1901)
        @"iPhone11,2": @"iPhone XS", // (model A2097, A2098)
        @"iPhone11,4": @"iPhone XS Max", // (model A1921, A2103)
        @"iPhone11,6": @"iPhone XS Max", // (model A2104)
        @"iPhone11,8": @"iPhone XR", // (model A1882, A1719, A2105)
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone12,8": @"iPhone SE", // (2nd Generation iPhone SE),
        @"iPhone13,1": @"iPhone 12 mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,6": @"iPhone SE", // (3nd Generation iPhone SE),
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        @"iPhone17,1": @"iPhone 16 Pro",
        @"iPhone17,2": @"iPhone 16 Pro Max",
        @"iPhone17,3": @"iPhone 16",
        @"iPhone17,4": @"iPhone 16 Plus",

        @"iPod1,1": @"iPod Touch", // (Original)
        @"iPod2,1": @"iPod Touch", // (Second Generation)
        @"iPod3,1": @"iPod Touch", // (Third Generation)
        @"iPod4,1": @"iPod Touch", // (Fourth Generation)
        @"iPod5,1": @"iPod Touch", // (Fifth Generation)
        @"iPod7,1": @"iPod Touch", // (Sixth Generation)
        @"iPod9,1": @"iPod Touch", // (Seventh Generation)

        @"iPad1,1": @"iPad",
        @"iPad1,2": @"iPad 3G",
        @"iPad2,1": @"iPad 2",
        @"iPad2,2": @"iPad 2",
        @"iPad2,3": @"iPad 2",
        @"iPad2,4": @"iPad 2",
        @"iPad3,1": @"iPad",
        @"iPad3,2": @"iPad",
        @"iPad3,3": @"iPad",
        @"iPad2,5": @"iPad mini",
        @"iPad2,6": @"iPad mini",
        @"iPad2,7": @"iPad mini",
        @"iPad3,4": @"iPad",
        @"iPad3,5": @"iPad",
        @"iPad3,6": @"iPad",
        @"iPad4,1": @"iPad Air",
        @"iPad4,2": @"iPad Air",
        @"iPad4,3": @"iPad Air",
        @"iPad4,4": @"iPad Mini 2",
        @"iPad4,5": @"iPad Mini 2",
        @"iPad4,6": @"iPad Mini 2",
        @"iPad4,7": @"iPad Mini 3",
        @"iPad4,8": @"iPad Mini 3",
        @"iPad4,9": @"iPad Mini 3",
        @"iPad5,1": @"iPad Mini 4",
        @"iPad5,2": @"iPad Mini 4",
        @"iPad5,3": @"iPad Air 2",
        @"iPad5,4": @"iPad Air 2",
        @"iPad6,3": @"iPad Pro 9.7-inch",
        @"iPad6,4": @"iPad Pro 9.7-inch",
        @"iPad6,7": @"iPad Pro 12.9-inch",
        @"iPad6,8":@"iPad Pro 12.9-inch",
        @"iPad6,11": @"iPad (5th generation)",
        @"iPad6,12": @"iPad (5th generation)",
        @"iPad7,1": @"iPad Pro 12.9-inch",
        @"iPad7,2": @"iPad Pro 12.9-inch",
        @"iPad7,3": @"iPad Pro 10.5-inch",
        @"iPad7,4": @"iPad Pro 10.5-inch",
        @"iPad7,5": @"iPad (6th generation)",
        @"iPad7,6": @"iPad (6th generation)",
        @"iPad7,11": @"iPad (7th generation)",
        @"iPad7,12": @"iPad (7th generation)",
        @"iPad8,1": @"iPad Pro 11-inch (3rd generation)",
        @"iPad8,2": @"iPad Pro 11-inch (3rd generation)",
        @"iPad8,3": @"iPad Pro 11-inch (3rd generation)",
        @"iPad8,4": @"iPad Pro 11-inch (3rd generation)",
        @"iPad8,5": @"iPad Pro 12.9-inch (3rd generation)",
        @"iPad8,6": @"iPad Pro 12.9-inch (3rd generation)",
        @"iPad8,7": @"iPad Pro 12.9-inch (3rd generation)",
        @"iPad8,8": @"iPad Pro 12.9-inch (3rd generation)",
        @"iPad8,9": @"iPad Pro 11-inch (4th generation)",
        @"iPad8,10": @"iPad Pro 11-inch (4th generation)",
        @"iPad8,11": @"iPad Pro 12.9-inch (4th generation)",
        @"iPad8,12": @"iPad Pro 12.9-inch (4th generation)",
        @"iPad11,1": @"iPad Mini 5",
        @"iPad11,2": @"iPad Mini 5",
        @"iPad11,3": @"iPad Air 3rd Gen (WiFi)",
        @"iPad11,4": @"iPad Air (3rd generation)",
        @"iPad11,6": @"iPad Air (3rd generation)",
        @"iPad11,7": @"iPad (8th generation)",
        @"iPad12,1": @"iPad (9th generation)",
        @"iPad12,2": @"iPad (9th generation)",
        @"iPad14,1": @"iPad Mini (6th generation)",
        @"iPad14,2": @"iPad Mini (6th generation)",
        @"iPad13,1": @"iPad Air (4th generation)",
        @"iPad13,2": @"iPad Air (4th generation)",
        @"iPad13,4": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,5": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,6": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,7": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,8": @"iPad Pro 12.9-inch (5th generation)",
        @"iPad13,9": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,10": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,11": @"iPad Pro 11-inch (5th generation)",
        @"iPad13,16": @"iPad Air (5th generation)",
        @"iPad13,17": @"iPad Air (5th generation)",
        @"iPad13,18": @"iPad (10th generation)",
        @"iPad13,19": @"iPad (10th generation)",
        @"iPad14,3": @"iPad Pro 11-inch (4th generation)",
        @"iPad14,4": @"iPad Pro 11-inch (4th generation)",
        @"iPad14,5": @"iPad Pro 12.9-inch (6th generation)",
        @"iPad14,6": @"iPad Pro 12.9-inch (6th generation)",
        @"iPad14,8": @"iPad Air (6th generation)",
        @"iPad14,9": @"iPad Air (6th generation)",
        @"iPad14,10": @"iPad Air (7th generation)",
        @"iPad14,11": @"iPad Air (7th generation)",
        @"iPad16,3": @"iPad Pro 11-inch (5th generation)",
        @"iPad16,4": @"iPad Pro 11-inch (5th generation)",
        @"iPad16,5": @"iPad Pro 12.9-inch (7th generation)",
        @"iPad16,6": @"iPad Pro 12.9-inch (7th generation)",

        @"AppleTV2,1": @"Apple TV", // Apple TV (2nd Generation)
        @"AppleTV3,1": @"Apple TV", // Apple TV (3rd Generation)
        @"AppleTV3,2": @"Apple TV", // Apple TV (3rd Generation - Rev A)
        @"AppleTV5,3": @"Apple TV", // Apple TV (4th Generation)
        @"AppleTV6,2": @"Apple TV 4K", // Apple TV 4K

        @"RealityDevice14,1": @"Apple Vision Pro" // Apple Vision Pro
    };
}

- (NSString *) getModel {
    NSString* deviceId = [self getDeviceId];
    NSDictionary* deviceNamesByCode = [self getDeviceNamesByCode];
    NSString* deviceName =[deviceNamesByCode valueForKey:deviceId];

    // Return the real device name if we have it
    if (deviceName) {
        return deviceName;
    }

    // If we don't have the real device name, try a generic
    if ([deviceId hasPrefix:@"iPod"]) {
        return @"iPod Touch";
    } else if ([deviceId hasPrefix:@"iPad"]) {
        return @"iPad";
    } else if ([deviceId hasPrefix:@"iPhone"]) {
        return @"iPhone";
    } else if ([deviceId hasPrefix:@"AppleTV"]) {
        return @"Apple TV";
    } else if ([deviceId hasPrefix:@"RealityDevice"]) {
        return @"Apple Vision";
    }

    // If we could not even get a generic, it's unknown
    return @"unknown";
}

- (NSString *) getCarrier {
#if (TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION)
    return @"unknown";
#else
    CTTelephonyNetworkInfo *netinfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [netinfo subscriberCellularProvider];
    if (carrier.carrierName != nil) {
        return carrier.carrierName;
    }
    return @"unknown";
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getCarrierSync) {
    return self.getCarrier;
}

RCT_EXPORT_METHOD(getCarrier:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getCarrier);
}

- (NSString *) getBuildId {
#if TARGET_OS_TV
    return @"unknown";
#else
    size_t bufferSize = 64;
    NSMutableData *buffer = [[NSMutableData alloc] initWithLength:bufferSize];
    int status = sysctlbyname("kern.osversion", buffer.mutableBytes, &bufferSize, NULL, 0);
    if (status != 0) {
        return @"unknown";
    }
    NSString* buildId = [[NSString alloc] initWithCString:buffer.mutableBytes encoding:NSUTF8StringEncoding];
    return buildId;
#endif
}

RCT_EXPORT_METHOD(getBuildId:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getBuildId);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getBuildIdSync) {
    return self.getBuildId;
}

- (NSString *) uniqueId {
    return [DeviceUID uid];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getUniqueIdSync) {
    return self.uniqueId;
}

RCT_EXPORT_METHOD(getUniqueId:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.uniqueId);
}

RCT_EXPORT_METHOD(syncUniqueId:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve([DeviceUID syncUid]);
}

- (NSString *) getDeviceId {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString* deviceId = [NSString stringWithCString:systemInfo.machine
                                            encoding:NSUTF8StringEncoding];
    #if TARGET_IPHONE_SIMULATOR
        deviceId = [NSString stringWithFormat:@"%s", getenv("SIMULATOR_MODEL_IDENTIFIER")];
    #endif
    return deviceId;
}


- (BOOL) isEmulator {
    #if TARGET_IPHONE_SIMULATOR
        return YES;
    #else
        return NO;
    #endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isEmulatorSync) {
    return @(self.isEmulator);
}

RCT_EXPORT_METHOD(isEmulator:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isEmulator));
}

- (BOOL) isTablet {
    if ([self getDeviceType] == DeviceTypeTablet) {
        return YES;
    } else {
        return NO;
    }
}

RCT_EXPORT_METHOD(getDeviceToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (@available(iOS 11.0, *)) {
        if (TARGET_IPHONE_SIMULATOR) {
            reject(@"NOT AVAILABLE", @"Device check is only available for physical devices", nil);
            return;
        }

        DCDevice *device = DCDevice.currentDevice;

        if ([device isSupported]) {
            [DCDevice.currentDevice generateTokenWithCompletionHandler:^(NSData * _Nullable token, NSError * _Nullable error) {
                if (error) {
                    reject(@"ERROR GENERATING TOKEN", error.localizedDescription, error);
                    return;
                }

                resolve([token base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed]);
            }];
        } else {
            reject(@"NOT SUPPORTED", @"Device check is not supported by this device", nil);
            return;
        }
    } else {
        reject(@"NOT AVAILABLE", @"Device check is only available for iOS > 11", nil);
        return;
    }
}

- (float) getFontScale {
    // Font scales based on font sizes from https://developer.apple.com/ios/human-interface-guidelines/visual-design/typography/
    float fontScale = 1.0;

    #if !TARGET_OS_VISION
        UITraitCollection *traitCollection = [[UIScreen mainScreen] traitCollection];

        // Shared application is unavailable in an app extension.
        if (traitCollection) {
            __block NSString *contentSize = nil;
            RCTUnsafeExecuteOnMainQueueSync(^{
                if (@available(iOS 10.0, tvOS 10.0, macCatalyst 13.0, *)) {
                    contentSize = traitCollection.preferredContentSizeCategory;
                } else {
                    // if we can't get contentSize, we'll fall back to 1.0
                }
            });

            if ([contentSize isEqual: @"UICTContentSizeCategoryXS"]) fontScale = 0.82;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryS"]) fontScale = 0.88;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryM"]) fontScale = 0.95;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryL"]) fontScale = 1.0;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryXL"]) fontScale = 1.12;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryXXL"]) fontScale = 1.23;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryXXXL"]) fontScale = 1.35;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryAccessibilityM"]) fontScale = 1.64;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryAccessibilityL"]) fontScale = 1.95;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryAccessibilityXL"]) fontScale = 2.35;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryAccessibilityXXL"]) fontScale = 2.76;
            else if ([contentSize isEqual: @"UICTContentSizeCategoryAccessibilityXXXL"]) fontScale = 3.12;
        }
    #endif

    return fontScale;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getFontScaleSync) {
    return @(self.getFontScale);
}

RCT_EXPORT_METHOD(getFontScale:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getFontScale));
}

- (double) getTotalMemory {
    return [NSProcessInfo processInfo].physicalMemory;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getTotalMemorySync) {
    return @(self.getTotalMemory);
}

RCT_EXPORT_METHOD(getTotalMemory:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getTotalMemory));
}

- (double) getTotalDiskCapacity {
    uint64_t totalSpace = 0;
    NSDictionary *storage = [self getStorageDictionary];

    if (storage) {
        NSNumber *fileSystemSizeInBytes = [storage objectForKey: NSFileSystemSize];
        totalSpace = [fileSystemSizeInBytes unsignedLongLongValue];
    }
    return (double) totalSpace;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getTotalDiskCapacitySync) {
    return @(self.getTotalDiskCapacity);
}

RCT_EXPORT_METHOD(getTotalDiskCapacity:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getTotalDiskCapacity));
}

- (double)getFreeDiskStorage:(NSString *)storageType {
    NSError *error = nil;

    // iOS 11 and above: Use NSURLVolumeAvailableCapacityForImportantUsageKey
    // https://developer.apple.com/documentation/foundation/urlresourcekey/checking_volume_storage_capacity
    if (@available(iOS 11.0, *)) {
        NSURL *fileURL = [NSURL fileURLWithPath:NSHomeDirectory()];
        NSString *capacityKey = [self keyForStorageType:storageType];
        NSDictionary *storageValues = [fileURL resourceValuesForKeys:@[capacityKey] error:&error];

        if (error) {
            NSLog(@"Error retrieving storage information: %@", error);
            return 0;
        }

        NSNumber *availableCapacity = [storageValues objectForKey:capacityKey];
        if (availableCapacity) {
            return (double)[availableCapacity unsignedLongLongValue];
        }
    } else {
        // Fallback for older iOS versions: Use NSFileSystemFreeSize
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error:&error];

        if (error) {
            NSLog(@"Error retrieving fallback storage information: %@", error);
            return 0;
        }

        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        if (freeFileSystemSizeInBytes) {
            return (double)[freeFileSystemSizeInBytes unsignedLongLongValue];
        }
    }

    return 0;
}

- (NSString *)keyForStorageType:(NSString *)storageType {
#if TARGET_OS_TV
    return NSURLVolumeAvailableCapacityKey;
#else
    if ([storageType isEqualToString:@"important"]) {
        return NSURLVolumeAvailableCapacityForImportantUsageKey;
    } else if ([storageType isEqualToString:@"opportunistic"]) {
        return NSURLVolumeAvailableCapacityForOpportunisticUsageKey;
    } else {
        return NSURLVolumeAvailableCapacityKey;
    }
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getFreeDiskStorageSync:(NSString *)storageType) {
    return @([self getFreeDiskStorage:storageType]);
}

RCT_EXPORT_METHOD(getFreeDiskStorage:(NSString *)storageType
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject) {
    double freeStorage = [self getFreeDiskStorage:storageType];
    resolve(@(freeStorage));
}

- (NSString *) getDeviceTypeName {
    return [DeviceTypeValues objectAtIndex: [self getDeviceType]];
}

- (NSArray *) getSupportedAbis {
    /* https://stackoverflow.com/questions/19859388/how-can-i-get-the-ios-device-cpu-architecture-in-runtime */
    const NXArchInfo *info = NXGetLocalArchInfo();
    NSString *typeOfCpu = [NSString stringWithUTF8String:info->description];
    return @[typeOfCpu];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getSupportedAbisSync) {
    return self.getSupportedAbis;
}

RCT_EXPORT_METHOD(getSupportedAbis:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getSupportedAbis);
}

- (NSString *) getIpAddress {
    NSString *address = @"0.0.0.0";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            sa_family_t addr_family = temp_addr->ifa_addr->sa_family;
            // Check for IPv4 or IPv6-only interfaces
            if(addr_family == AF_INET || addr_family == AF_INET6) {
                NSString* ifname = [NSString stringWithUTF8String:temp_addr->ifa_name];
                    if(
                        // Check if interface is en0 which is the wifi connection the iPhone
                        // and the ethernet connection on the Apple TV
                        [ifname isEqualToString:@"en0"] ||
                        // Check if interface is en1 which is the wifi connection on the Apple TV
                        [ifname isEqualToString:@"en1"]
                    ) {
                        const struct sockaddr_in *addr = (const struct sockaddr_in*)temp_addr->ifa_addr;
                        socklen_t addr_len = addr_family == AF_INET ? INET_ADDRSTRLEN : INET6_ADDRSTRLEN;
                        char addr_buffer[addr_len];
                        // We use inet_ntop because it also supports getting an address from
                        // interfaces that are IPv6-only
                        const char *netname = inet_ntop(addr_family, &addr->sin_addr, addr_buffer, addr_len);

                         // Get NSString from C String
                        address = [NSString stringWithUTF8String:netname];
                    }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getIpAddressSync) {
    return self.getIpAddress;
}

RCT_EXPORT_METHOD(getIpAddress:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getIpAddress);
}

- (BOOL) isPinOrFingerprintSet {
#if TARGET_OS_TV
    return NO;
#else
    LAContext *context = [[LAContext alloc] init];
    return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil];
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isPinOrFingerprintSetSync) {
    return @(self.isPinOrFingerprintSet);
}

RCT_EXPORT_METHOD(isPinOrFingerprintSet:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isPinOrFingerprintSet));
}

- (void) batteryLevelDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }

    float batteryLevel = self.getBatteryLevel;
    [self sendEventWithName:@"RNDeviceInfo_batteryLevelDidChange" body:@(batteryLevel)];

    if (batteryLevel <= _lowBatteryThreshold) {
        [self sendEventWithName:@"RNDeviceInfo_batteryLevelIsLow" body:@(batteryLevel)];
    }
}

- (void) powerStateDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }
    [self sendEventWithName:@"RNDeviceInfo_powerStateDidChange" body:self.powerState];
}

- (void) headphoneConnectionDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }
    BOOL isConnected = [self isHeadphonesConnected];
    [self sendEventWithName:@"RNDeviceInfo_headphoneConnectionDidChange" body:[NSNumber numberWithBool:isConnected]];
}

- (void) headphoneWiredConnectionDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }
    BOOL isConnected = [self isWiredHeadphonesConnected];
    [self sendEventWithName:@"RNDeviceInfo_headphoneWiredConnectionDidChange" body:[NSNumber numberWithBool:isConnected]];
}

- (void) headphoneBluetoothConnectionDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }
    BOOL isConnected = [self isBluetoothHeadphonesConnected];
    [self sendEventWithName:@"RNDeviceInfo_headphoneBluetoothConnectionDidChange" body:[NSNumber numberWithBool:isConnected]];
}

- (void) brightnessDidChange:(NSNotification *)notification {
    if (!hasListeners) {
        return;
    }
    [self sendEventWithName:@"RNDeviceInfo_brightnessDidChange" body:self.getBrightness];
}

- (NSDictionary *) powerState {
#if RCT_DEV && (!TARGET_IPHONE_SIMULATOR) && !TARGET_OS_TV
    if ([UIDevice currentDevice].isBatteryMonitoringEnabled != true) {
        RCTLogWarn(@"Battery monitoring is not enabled. "
                   "You need to enable monitoring with `[UIDevice currentDevice].batteryMonitoringEnabled = TRUE`");
    }
#endif
#if RCT_DEV && TARGET_IPHONE_SIMULATOR && !TARGET_OS_TV
    if ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateUnknown) {
        RCTLogWarn(@"Battery state `unknown` and monitoring disabled, this is normal for simulators and tvOS.");
    }
#endif
    float batteryLevel = self.getBatteryLevel;

    return @{
#if TARGET_OS_TV
             @"batteryLevel": @(batteryLevel),
             @"batteryState": @"full",
#else
             @"batteryLevel": @(batteryLevel),
             @"batteryState": [@[@"unknown", @"unplugged", @"charging", @"full"] objectAtIndex: [UIDevice currentDevice].batteryState],
             @"lowPowerMode": @([NSProcessInfo processInfo].isLowPowerModeEnabled),
#endif
             };
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getPowerStateSync) {
    return self.powerState;
}

RCT_EXPORT_METHOD(getPowerState:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.powerState);
}

- (float) getBatteryLevel {
#if TARGET_OS_TV
    return [@1 floatValue];
#else
    return [@([UIDevice currentDevice].batteryLevel) floatValue];
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getBatteryLevelSync) {
    return @(self.getBatteryLevel);
}

RCT_EXPORT_METHOD(getBatteryLevel:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getBatteryLevel));
}

- (BOOL) isBatteryCharging {
    return [self.powerState[@"batteryState"] isEqualToString:@"charging"];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isBatteryChargingSync) {
    return @(self.isBatteryCharging);
}

RCT_EXPORT_METHOD(isBatteryCharging:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isBatteryCharging));
}

- (BOOL) isLocationEnabled {
    return [CLLocationManager locationServicesEnabled];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isLocationEnabledSync) {
    return @(self.isLocationEnabled);
}

RCT_EXPORT_METHOD(isLocationEnabled:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isLocationEnabled));
}

- (BOOL) isHeadphonesConnected {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones]) {
            return YES;
        }
        if ([[desc portType] isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
            return YES;
        }
        if ([[desc portType] isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return YES;
        }
    }
    return NO;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isHeadphonesConnectedSync) {
    return @(self.isHeadphonesConnected);
}

RCT_EXPORT_METHOD(isHeadphonesConnected:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isHeadphonesConnected));
}

- (BOOL) isWiredHeadphonesConnected {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones]) {
            return YES;
        }
    }
    return NO;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isWiredHeadphonesConnectedSync) {
    return @(self.isWiredHeadphonesConnected);
}

RCT_EXPORT_METHOD(isWiredHeadphonesConnected:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isWiredHeadphonesConnected));
}

- (BOOL) isBluetoothHeadphonesConnected {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
            return YES;
        }
        if ([[desc portType] isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return YES;
        }
    }
    return NO;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isBluetoothHeadphonesConnectedSync) {
    return @(self.isBluetoothHeadphonesConnected);
}

RCT_EXPORT_METHOD(isBluetoothHeadphonesConnected:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isBluetoothHeadphonesConnected));
}

- (unsigned long) getUsedMemory {
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    if (kerr != KERN_SUCCESS) {
      return -1;
    }

    return (unsigned long)info.resident_size;
}

RCT_EXPORT_METHOD(getUsedMemory:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    unsigned long usedMemory = self.getUsedMemory;
    if (usedMemory == -1) {
        reject(@"fetch_error", @"task_info failed", nil);
    } else {
        resolve(@(usedMemory));
    }
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getUsedMemorySync) {
    return @(self.getUsedMemory);
}

RCT_EXPORT_METHOD(getUserAgent:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
#if TARGET_OS_TV
    reject(@"not_available_error", @"not available on tvOS", nil);
#else
    __weak RNDeviceInfo *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong RNDeviceInfo *strongSelf = weakSelf;
        if (strongSelf) {
            // Save WKWebView (it might deallocate before we ask for user Agent)
            __block WKWebView *webView = [[WKWebView alloc] init];

            [webView evaluateJavaScript:@"window.navigator.userAgent;" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
                if (error) {
                    reject(@"getUserAgentError", error.localizedDescription, error);
                }else{
                    resolve([NSString stringWithFormat:@"%@", result]);
                }
                // Destroy the WKWebView after task is complete
                webView = nil;
            }];
        }
    });
#endif
}

- (NSDictionary *) getAvailableLocationProviders {
#if !TARGET_OS_TV
    return @{
              @"locationServicesEnabled": [NSNumber numberWithBool: [CLLocationManager locationServicesEnabled]],
              @"significantLocationChangeMonitoringAvailable": [NSNumber numberWithBool: [CLLocationManager significantLocationChangeMonitoringAvailable]],
              @"headingAvailable": [NSNumber numberWithBool: [CLLocationManager headingAvailable]],
              @"isRangingAvailable": [NSNumber numberWithBool: [CLLocationManager isRangingAvailable]]
              };
#else
    return @{
              @"locationServicesEnabled": [NSNumber numberWithBool: [CLLocationManager locationServicesEnabled]]
              };
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getAvailableLocationProvidersSync) {
    return self.getAvailableLocationProviders;
}

RCT_EXPORT_METHOD(getAvailableLocationProviders:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getAvailableLocationProviders);
}

#pragma mark - Installer Package Name -

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getInstallerPackageNameSync) {
    return [EnvironmentValues objectAtIndex:[EnvironmentUtil currentAppEnvironment]];
}

RCT_EXPORT_METHOD(getInstallerPackageName:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve([EnvironmentValues objectAtIndex:[EnvironmentUtil currentAppEnvironment]]);
}

- (NSNumber *) getBrightness {
#if !TARGET_OS_TV && !TARGET_OS_VISION
    return @([UIScreen mainScreen].brightness);
#else
    return @(-1);
#endif
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getBrightnessSync) {
    return self.getBrightness;
}

RCT_EXPORT_METHOD(getBrightness:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.getBrightness);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getFirstInstallTimeSync) {
    return @(self.getFirstInstallTime);
}

RCT_EXPORT_METHOD(getFirstInstallTime:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getFirstInstallTime));
}

- (long long) getFirstInstallTime {
    NSURL* urlToDocumentsFolder = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSError *error;
    NSDate *installDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:urlToDocumentsFolder.path error:&error] objectForKey:NSFileCreationDate];
    return [@(floor([installDate timeIntervalSince1970] * 1000)) longLongValue];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getStartupTimeSync) {
    return @(self.getStartupTime);
}

RCT_EXPORT_METHOD(getStartupTime:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.getStartupTime));
}
 
// Reads the process startup time and returns it in milliseconds since 1970
// Reading the process startup time from the system is more accurate than comparing a date which is initiallized at launch with the current time
- (long long) getStartupTime {
    size_t len = 4;
    int mib[len];
    struct kinfo_proc kp;

    sysctlnametomib("kern.proc.pid", mib, &len);
    mib[3] = getpid();
    len = sizeof(kp);
    sysctl(mib, 4, &kp, &len, NULL, 0);

    struct timeval startTime = kp.kp_proc.p_un.__p_starttime;
    double startTimeMilliSeconds = startTime.tv_sec * 1e3 + startTime.tv_usec / 1e3;
    return [@(floor(startTimeMilliSeconds)) longLongValue];
}

#pragma mark - dealloc -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
