//
//  SileoBrowserPickerRootListController.m
//  SileoBrowserPicker Settings
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Forward declare PSListController (provided by Preferences.app at runtime)
@interface PSListController : UIViewController {
    NSArray *_specifiers;
}
- (NSArray *)specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name;
@end

@interface SileoBrowserPickerRootListController : PSListController
@end

@implementation SileoBrowserPickerRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"SileoBrowserPicker"];
    }
    return _specifiers;
}

- (NSString *)title {
    return @"Sileo 浏览器选择";
}

@end
