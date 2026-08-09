#import "LFOUIResolver.h"

#include <ctype.h>
#include <sqlite3.h>

@interface LFOUIResolver ()
@property(nonatomic, assign) sqlite3 *database;
@property(nonatomic, assign) sqlite3_stmt *lookupStatement;
@property(nonatomic, strong) NSLock *lock;
@end

@implementation LFOUIResolver

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _lock = [NSLock new];
        NSString *path = [NSBundle.mainBundle pathForResource:@"OUI"
                                                       ofType:@"sqlite"];
        if (path != nil &&
            sqlite3_open_v2(path.fileSystemRepresentation, &_database,
                            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                            NULL) == SQLITE_OK) {
            const char *query =
                "SELECT vendor.name FROM prefix "
                "JOIN vendor ON vendor.id = prefix.vendor_id "
                "WHERE prefix.value = ?1 LIMIT 1";
            if (sqlite3_prepare_v2(_database, query, -1, &_lookupStatement,
                                   NULL) != SQLITE_OK) {
                sqlite3_close(_database);
                _database = NULL;
            }
        }
    }
    return self;
}

- (void)dealloc {
    if (_lookupStatement != NULL) sqlite3_finalize(_lookupStatement);
    if (_database != NULL) sqlite3_close(_database);
}

- (NSString *)normalizedMACAddress:(NSString *)macAddress {
    NSMutableString *result = [NSMutableString stringWithCapacity:12];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:
        @"0123456789abcdefABCDEF"];
    for (NSUInteger index = 0; index < macAddress.length; index++) {
        unichar character = [macAddress characterAtIndex:index];
        if ([hex characterIsMember:character]) {
            [result appendFormat:@"%C",
                                 (unichar)toupper((unsigned char)character)];
        }
    }
    return result.length == 12 ? result : nil;
}

- (NSString *)vendorForMACAddress:(NSString *)macAddress
               locallyAdministered:(BOOL *)locallyAdministered {
    NSString *normalized = [self normalizedMACAddress:macAddress];
    if (normalized == nil) return nil;

    unsigned int firstByte = 0;
    [[NSScanner scannerWithString:[normalized substringToIndex:2]]
        scanHexInt:&firstByte];
    BOOL local = (firstByte & 0x02U) != 0;
    if (locallyAdministered != NULL) *locallyAdministered = local;
    if (local || self.lookupStatement == NULL) return nil;

    [self.lock lock];
    NSString *vendor = nil;
    for (NSNumber *length in @[@9, @7, @6]) {
        NSString *prefix = [normalized substringToIndex:length.unsignedIntegerValue];
        sqlite3_reset(self.lookupStatement);
        sqlite3_clear_bindings(self.lookupStatement);
        sqlite3_bind_text(self.lookupStatement, 1, prefix.UTF8String, -1,
                          SQLITE_TRANSIENT);
        if (sqlite3_step(self.lookupStatement) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(self.lookupStatement, 0);
            if (text != NULL) vendor = [NSString stringWithUTF8String:(const char *)text];
            break;
        }
    }
    sqlite3_reset(self.lookupStatement);
    [self.lock unlock];
    return vendor;
}

@end
