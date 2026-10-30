// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"
#import <sqlite3.h>

static sqlite3 *gDatabase = NULL;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  BOOL ok = [super application:application didFinishLaunchingWithOptions:launchOptions];
  FlutterViewController *controller =
      (FlutterViewController *)self.window.rootViewController;
  if (controller != nil) {
    [self attachChannels:controller];
  }
  return ok;
}

- (void)attachChannels:(FlutterViewController *)controller {
  FlutterMethodChannel *sql = [FlutterMethodChannel
      methodChannelWithName:@"ru.smp.smp_guide/sql"
            binaryMessenger:controller.binaryMessenger];
  [sql setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    @try {
      if ([call.method isEqualToString:@"open"]) {
        [self openDatabase];
        result(nil);
      } else if ([call.method isEqualToString:@"exec"]) {
        NSDictionary *args = call.arguments;
        [self exec:args[@"sql"] values:args[@"args"]];
        result(nil);
      } else if ([call.method isEqualToString:@"query"]) {
        NSDictionary *args = call.arguments;
        result([self query:args[@"sql"] values:args[@"args"]]);
      } else {
        result(FlutterMethodNotImplemented);
      }
    } @catch (NSException *exception) {
      result([FlutterError errorWithCode:@"sqlite"
                                 message:exception.reason
                                 details:nil]);
    }
  }];

  FlutterMethodChannel *share = [FlutterMethodChannel
      methodChannelWithName:@"ru.smp.smp_guide/share"
            binaryMessenger:controller.binaryMessenger];
  [share setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    if (![call.method isEqualToString:@"share"]) {
      result(FlutterMethodNotImplemented);
      return;
    }
    NSString *text = [call.arguments isKindOfClass:[NSString class]]
                         ? call.arguments
                         : [call.arguments description];
    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:@[ text ?: @"" ]
        applicationActivities:nil];
    [controller presentViewController:activity animated:YES completion:nil];
    result(nil);
  }];
}

- (void)openDatabase {
  if (gDatabase != NULL) return;
  NSString *directory = NSSearchPathForDirectoriesInDomains(
                            NSDocumentDirectory, NSUserDomainMask, YES)
                            .firstObject;
  NSString *path = [directory stringByAppendingPathComponent:@"smp_guide.sqlite"];
  if (sqlite3_open([path UTF8String], &gDatabase) != SQLITE_OK) {
    [NSException raise:@"sqlite" format:@"open failed"];
  }
}

- (void)exec:(NSString *)sql values:(NSArray *)values {
  sqlite3_stmt *statement = NULL;
  if (sqlite3_prepare_v2(gDatabase, [sql UTF8String], -1, &statement, NULL) != SQLITE_OK) {
    [NSException raise:@"sqlite" format:@"%s", sqlite3_errmsg(gDatabase)];
  }
  [self bind:statement values:values];
  int code = sqlite3_step(statement);
  sqlite3_finalize(statement);
  if (code != SQLITE_DONE && code != SQLITE_ROW) {
    [NSException raise:@"sqlite" format:@"%s", sqlite3_errmsg(gDatabase)];
  }
}

- (NSArray *)query:(NSString *)sql values:(NSArray *)values {
  sqlite3_stmt *statement = NULL;
  if (sqlite3_prepare_v2(gDatabase, [sql UTF8String], -1, &statement, NULL) != SQLITE_OK) {
    [NSException raise:@"sqlite" format:@"%s", sqlite3_errmsg(gDatabase)];
  }
  [self bind:statement values:values];
  NSMutableArray *rows = [NSMutableArray array];
  while (sqlite3_step(statement) == SQLITE_ROW) {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    int columns = sqlite3_column_count(statement);
    for (int index = 0; index < columns; index++) {
      NSString *name = [NSString stringWithUTF8String:sqlite3_column_name(statement, index)];
      switch (sqlite3_column_type(statement, index)) {
        case SQLITE_NULL:
          row[name] = [NSNull null];
          break;
        case SQLITE_INTEGER:
          row[name] = @(sqlite3_column_int64(statement, index));
          break;
        case SQLITE_FLOAT:
          row[name] = @(sqlite3_column_double(statement, index));
          break;
        default: {
          const unsigned char *text = sqlite3_column_text(statement, index);
          row[name] = text ? [NSString stringWithUTF8String:(const char *)text] : @"";
          break;
        }
      }
    }
    [rows addObject:row];
  }
  sqlite3_finalize(statement);
  return rows;
}

- (void)bind:(sqlite3_stmt *)statement values:(NSArray *)values {
  if (![values isKindOfClass:[NSArray class]]) return;
  for (NSUInteger i = 0; i < values.count; i++) {
    id value = values[i];
    int index = (int)i + 1;
    if (value == nil || value == [NSNull null]) {
      sqlite3_bind_null(statement, index);
    } else if ([value isKindOfClass:[NSNumber class]]) {
      const char *type = [value objCType];
      if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
        sqlite3_bind_double(statement, index, [value doubleValue]);
      } else {
        sqlite3_bind_int64(statement, index, [value longLongValue]);
      }
    } else {
      sqlite3_bind_text(statement, index, [[value description] UTF8String], -1, SQLITE_TRANSIENT);
    }
  }
}

@end
