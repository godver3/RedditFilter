#import <AppSettingsViewController.h>
#import "FeedFilterSettingsViewController.h"

NSBundle *redditFilterBundle;

extern UIImage *iconWithName(NSString *iconName);
extern NSString *localizedString(NSString *key, NSString *table);

@interface AppSettingsViewController ()
@property(nonatomic, assign) NSInteger feedFilterSectionIndex;
@end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                        NSError *error))completionHandler {
  if (![request.URL.host hasPrefix:@"gql"] || !request.HTTPBody) return %orig;
  NSError *error;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody
                                                       options:0
                                                         error:&error];
  if (error || ![json[@"operationName"] isEqualToString:@"GetAllExperimentVariants"])
    return %orig;
  void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) =
      ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return completionHandler(data, response, error);
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                             options:NSJSONReadingMutableContainers
                                                               error:&error];
        if (error || !json) return completionHandler(data, response, error);
        for (NSMutableDictionary *experimentVariant in json[@"data"][@"experimentVariants"])
          if ([experimentVariant[@"experimentName"] isEqualToString:@"ios_swiftui_app_settings"])
            experimentVariant[@"name"] = @"disabled";
        data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        completionHandler(data, response, error);
      };
  return %orig(request, newCompletionHandler);
}
%end

%hook AppSettingsViewController
%property(nonatomic, assign) NSInteger feedFilterSectionIndex;
- (void)viewDidLoad {
  %orig;
  
  NSLog(@"[RedditFilter] viewDidLoad called, searching for feed options section...");
  
  for (int section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
    BaseTableReusableView *headerView = (BaseTableReusableView *)[self tableView:self.tableView
                                                          viewForHeaderInSection:section];
    if (!headerView) {
      NSLog(@"[RedditFilter] Section %d: No header view", section);
      continue;
    }
    BaseLabel *label = headerView.contentView.subviews[0];
    NSLog(@"[RedditFilter] Section %d: Header text = '%@'", section, label.text);
    
    for (NSString *key in @[ @"drawer.settings.feedOptions", @"drawer.settings.viewOptions" ]) {
      NSString *localizedText = [localizedString(key, @"user") uppercaseString];
      NSLog(@"[RedditFilter] Checking key '%@' -> localized: '%@'", key, localizedText);
      if ([label.text isEqualToString:localizedText]) {
        self.feedFilterSectionIndex = section;
        NSLog(@"[RedditFilter] Found matching section: %d", section);
        return;
      }
    }
  }
  
  // Try alternative localization keys that Reddit might be using now
  NSLog(@"[RedditFilter] Trying alternative keys...");
  for (int section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
    BaseTableReusableView *headerView = (BaseTableReusableView *)[self tableView:self.tableView
                                                          viewForHeaderInSection:section];
    if (!headerView) continue;
    BaseLabel *label = headerView.contentView.subviews[0];
    
    NSArray *alternativeKeys = @[
      @"settings.feed.options",
      @"settings.view.options", 
      @"feed.options",
      @"view.options",
      @"content.options",
      @"display.options"
    ];
    
    for (NSString *key in alternativeKeys) {
      NSString *localizedText = [localizedString(key, @"user") uppercaseString];
      if (localizedText && [label.text isEqualToString:localizedText]) {
        self.feedFilterSectionIndex = section;
        NSLog(@"[RedditFilter] Found matching section with alternative key '%@': %d", key, section);
        return;
      }
    }
  }
  
  // Fallback: look for any section with "feed" or "view" in the text
  NSLog(@"[RedditFilter] Trying text-based matching...");
  for (int section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
    BaseTableReusableView *headerView = (BaseTableReusableView *)[self tableView:self.tableView
                                                          viewForHeaderInSection:section];
    if (!headerView) continue;
    BaseLabel *label = headerView.contentView.subviews[0];
    
    NSString *labelText = [label.text lowercaseString];
    if ([labelText containsString:@"feed"] || [labelText containsString:@"view"] || 
        [labelText containsString:@"content"] || [labelText containsString:@"display"]) {
      self.feedFilterSectionIndex = section;
      NSLog(@"[RedditFilter] Found section by text matching: %d ('%@')", section, label.text);
      return;
    }
  }
  
  // Final fallback: use first non-empty section
  for (int section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
    NSInteger rowCount = [self tableView:self.tableView numberOfRowsInSection:section];
    if (rowCount > 0) {
      self.feedFilterSectionIndex = section;
      NSLog(@"[RedditFilter] Using first non-empty section: %d (rows: %ld)", section, (long)rowCount);
      return;
    }
  }
  
  self.feedFilterSectionIndex = 0;
  NSLog(@"[RedditFilter] Using fallback section: 0");
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  NSInteger result = %orig;
  if (section == self.feedFilterSectionIndex) result++;
  return result;
}
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.section == self.feedFilterSectionIndex &&
      indexPath.row == [self tableView:tableView numberOfRowsInSection:indexPath.section] - 1) {
    NSLog(@"[RedditFilter] Creating filter cell for section %ld, row %ld", (long)indexPath.section, (long)indexPath.row);
    
    UIImage *iconImage = [iconWithName(@"icon_filter") ?: iconWithName(@"icon-filter-outline")
        imageScaledToSize:CGSizeMake(20, 20)];
    UIImage *accessoryIconImage =
        [iconWithName(@"icon_forward") imageScaledToSize:CGSizeMake(20, 20)];
    
    NSLog(@"[RedditFilter] Icon image: %@, Accessory icon: %@", iconImage ? @"found" : @"not found", accessoryIconImage ? @"found" : @"not found");
    
    NSString *titleText = [redditFilterBundle
                              localizedStringForKey:@"filter.settings.title"
                                              value:@"Feed filter"
                                              table:nil];
    NSLog(@"[RedditFilter] Title text: '%@'", titleText);
    
    ImageLabelTableViewCell *cell =
        [self dequeueSettingsCellForTableView:tableView
                                    indexPath:indexPath
                                 leadingImage:iconImage
                                         text:titleText];
    [cell setCustomAccessoryImage:accessoryIconImage];
    
    NSLog(@"[RedditFilter] Cell created successfully: %@", cell);
    return cell;
  }
  return %orig;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.section == self.feedFilterSectionIndex &&
      indexPath.row == [self tableView:tableView numberOfRowsInSection:indexPath.section] - 1) {
    [self.navigationController
        pushViewController:[(FeedFilterSettingsViewController *)[objc_getClass(
                               "FeedFilterSettingsViewController") alloc]
                               initWithStyle:UITableViewStyleGrouped]
                  animated:YES];
    return;
  }
  %orig;
}
%end

%ctor {
  NSLog(@"[RedditFilter] Constructor called, loading bundle...");
  
  redditFilterBundle = [NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:@"RedditFilter"
                                                                              ofType:@"bundle"]];
  if (redditFilterBundle) {
    NSLog(@"[RedditFilter] Bundle loaded from main bundle: %@", redditFilterBundle.bundlePath);
  } else {
    NSLog(@"[RedditFilter] Bundle not found in main bundle, trying package path...");
    redditFilterBundle = [NSBundle bundleWithPath:@THEOS_PACKAGE_INSTALL_PREFIX
                                   @"/Library/Application Support/RedditFilter.bundle"];
    if (redditFilterBundle) {
      NSLog(@"[RedditFilter] Bundle loaded from package path: %@", redditFilterBundle.bundlePath);
    } else {
      NSLog(@"[RedditFilter] Bundle not found in package path either!");
    }
  }
}
