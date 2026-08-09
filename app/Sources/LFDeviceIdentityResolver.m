#import "LFDeviceIdentityResolver.h"

#import "LFOUIResolver.h"

@interface LFDeviceIdentityResolver ()
@property(nonatomic, strong) LFOUIResolver *ouiResolver;
@end

@implementation LFDeviceIdentityResolver

- (instancetype)init {
    self = [super init];
    if (self != nil) _ouiResolver = [LFOUIResolver new];
    return self;
}

- (NSArray<NSString *> *)stringsInEvidence:(NSDictionary *)evidence {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (NSString *key in @[@"names", @"hostnames", @"services"]) {
        for (id value in evidence[key]) {
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                [strings addObject:value];
            }
        }
    }
    return strings;
}

- (NSString *)preferredNameFromEvidence:(NSDictionary *)evidence {
    NSArray<NSString *> *names = evidence[@"names"] ?: @[];
    NSArray<NSString *> *hostnames = evidence[@"hostnames"] ?: @[];
    NSString *name = names.firstObject ?: hostnames.firstObject;
    while ([name hasSuffix:@"."]) name = [name substringToIndex:name.length - 1];
    if ([[name lowercaseString] hasSuffix:@".local"]) {
        name = [name substringToIndex:name.length - 6];
    }
    return name.length > 0 ? name : nil;
}

- (BOOL)text:(NSString *)text containsAny:(NSArray<NSString *> *)needles {
    for (NSString *needle in needles) {
        if ([text containsString:needle]) return YES;
    }
    return NO;
}

- (NSDictionary<NSString *, id> *)identityForDevice:(NSDictionary *)device
                                            evidence:(NSDictionary *)evidence {
    NSString *macAddress = device[@"mac"] ?: @"";
    BOOL locallyAdministered = NO;
    NSString *vendor = [self.ouiResolver vendorForMACAddress:macAddress
                                        locallyAdministered:&locallyAdministered];
    NSString *name = [self preferredNameFromEvidence:evidence];
    NSString *evidenceText = [[[self stringsInEvidence:evidence]
        componentsJoinedByString:@" "] lowercaseString];
    NSString *vendorText = vendor.lowercaseString ?: @"";

    NSString *platform = @"Unknown device";
    NSString *confidence = @"Unknown";
    NSString *reason = locallyAdministered
        ? @"Private or locally administered MAC; OUI vendor lookup is unavailable."
        : (vendor != nil ? @"Vendor from offline OUI data." : @"No identity evidence found.");

    if ([device[@"gateway"] boolValue]) {
        platform = @"Router / gateway";
        confidence = @"High";
        reason = @"This address is the active default gateway.";
    } else if ([evidenceText containsString:@"ipad"]) {
        platform = @"iPad";
        confidence = @"High";
        reason = @"Bonjour name or service identifies an iPad.";
    } else if ([evidenceText containsString:@"iphone"]) {
        platform = @"iPhone";
        confidence = @"High";
        reason = @"Bonjour name or service identifies an iPhone.";
    } else if ([self text:evidenceText containsAny:@[@"apple tv", @"appletv"]]) {
        platform = @"Apple TV";
        confidence = @"High";
        reason = @"Bonjour name identifies an Apple TV.";
    } else if ([self text:evidenceText
             containsAny:@[@"macbook", @"imac", @"mac mini", @"mac-pro"]]) {
        platform = @"Mac";
        confidence = @"High";
        reason = @"Bonjour name identifies a Mac.";
    } else if ([self text:evidenceText
             containsAny:@[@"android tv", @"androidtv", @"_androidtvremote2",
                            @"nvidia shield", @"bravia"]]) {
        platform = @"Android TV";
        confidence = @"High";
        reason = @"Bonjour name or service identifies an Android TV device.";
    } else if ([evidenceText containsString:@"_googlecast._tcp"]) {
        platform = @"Android TV / Google Cast";
        confidence = @"Medium";
        reason = @"The device advertises Google Cast; its exact OS is not exposed.";
    } else if ([evidenceText containsString:@"android"]) {
        platform = @"Android";
        confidence = @"High";
        reason = @"Bonjour name or service identifies Android.";
    } else if ([self text:evidenceText
             containsAny:@[@"desktop-", @"laptop-", @"windows", @"_rdp._tcp"]]) {
        platform = @"Windows";
        confidence = @"Medium";
        reason = @"The hostname or advertised service is typical of Windows.";
    } else if ([self text:evidenceText
             containsAny:@[@"ubuntu", @"debian", @"raspberrypi", @"raspberry pi",
                            @"pi-hole", @"linux"]]) {
        platform = @"Linux";
        confidence = @"High";
        reason = @"Bonjour hostname identifies a Linux system.";
    } else if ([vendorText containsString:@"apple"]) {
        platform = @"Apple device";
        confidence = @"Low";
        reason = @"The OUI belongs to Apple, but does not distinguish iPhone, iPad, Mac, or Apple TV.";
    } else if ([vendorText containsString:@"microsoft"]) {
        platform = @"Windows / Microsoft device";
        confidence = @"Low";
        reason = @"The OUI belongs to Microsoft; the exact product is unknown.";
    } else if ([vendorText containsString:@"raspberry pi"]) {
        platform = @"Linux / Raspberry Pi";
        confidence = @"Medium";
        reason = @"The OUI belongs to Raspberry Pi.";
    } else if ([self text:vendorText
             containsAny:@[@"google", @"xiaomi", @"oneplus", @"oppo", @"vivo",
                            @"huawei", @"motorola mobility"]]) {
        platform = @"Likely Android";
        confidence = @"Low";
        reason = @"The vendor commonly makes Android devices, but OUI alone cannot prove the OS.";
    } else if ([vendorText containsString:@"roku"]) {
        platform = @"Roku";
        confidence = @"Medium";
        reason = @"The OUI belongs to Roku.";
    } else if ([vendorText containsString:@"amazon"]) {
        platform = @"Amazon / Fire device";
        confidence = @"Low";
        reason = @"The OUI belongs to Amazon; the exact product is unknown.";
    }

    return @{
        @"name" : name ?: @"",
        @"vendor" : vendor ?: (locallyAdministered
            ? @"Private / randomized MAC" : @"Unknown vendor"),
        @"platform" : platform,
        @"confidence" : confidence,
        @"reason" : reason,
        @"locallyAdministered" : @(locallyAdministered),
    };
}

@end
