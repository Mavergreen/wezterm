#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static void emit(id value) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if (!data) { fprintf(stderr, "%s\n", [[error description] UTF8String]); exit(2); }
    fwrite([data bytes], 1, [data length], stdout);
    putchar('\n');
}

static NSString *text(const char *value) {
    NSString *result = [NSString stringWithUTF8String:value];
    if (!result) { fprintf(stderr, "invalid UTF-8 argument\n"); exit(2); }
    return result;
}

static pid_t process(const char *value) {
    char *end = NULL;
    long result = strtol(value, &end, 10);
    if (result <= 0 || result > INT_MAX || !end || *end) exit(2);
    return (pid_t)result;
}

static BOOL owned(NSRunningApplication *app, NSString *path) {
    return app && [[app bundleIdentifier] isEqualToString:@"dev.mavergreen.wezterm"] &&
        [[[[app bundleURL] path] stringByResolvingSymlinksInPath]
            isEqualToString:[path stringByResolvingSymlinksInPath]];
}

static NSArray *windows(pid_t pid) {
    NSArray *all = [(NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID) autorelease];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *row in all) {
        if ([row[(NSString *)kCGWindowOwnerPID] intValue] != pid || [row[(NSString *)kCGWindowLayer] intValue] != 0) continue;
        [result addObject:@{@"id": row[(NSString *)kCGWindowNumber],
                            @"title": row[(NSString *)kCGWindowName] ?: @"",
                            @"bounds": row[(NSString *)kCGWindowBounds]}];
    }
    return result;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 4) return 2;
        NSString *mode = text(argv[1]);
        NSString *path = text(argv[2]);
        if (![[[NSBundle bundleWithPath:path] bundleIdentifier] isEqualToString:@"dev.mavergreen.wezterm"]) return 2;
        if ([mode isEqualToString:@"launch"]) {
            if (argc != 5 && argc != 6) return 2;
            NSString *run = text(argv[3]);
            NSString *config = text(argv[4]);
            NSString *home = argc == 6 ? text(argv[5]) : [run stringByAppendingPathComponent:@"home"];
            NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
            for (NSString *key in @[@"WEZTERM_CONFIG_FILE", @"WEZTERM_CONFIG_DIR", @"WEZTERM_UNIX_DOMAIN", @"WEZTERM_PANE"]) [env removeObjectForKey:key];
            env[@"HOME"] = home;
            env[@"XDG_CONFIG_HOME"] = [home stringByAppendingPathComponent:@"config"];
            env[@"XDG_CACHE_HOME"] = [home stringByAppendingPathComponent:@"cache"];
            env[@"XDG_DATA_HOME"] = [home stringByAppendingPathComponent:@"data"];
            env[@"XDG_RUNTIME_DIR"] = [home stringByAppendingPathComponent:@"runtime"];
            env[@"TERMINFO"] = [path stringByAppendingPathComponent:@"Contents/Resources/terminfo"];
            env[@"WEZTERM_LOG"] = @"debug";
            env[@"LANG"] = @"en_US.UTF-8";
            env[@"LC_ALL"] = @"en_US.UTF-8";
            NSDictionary *configuration = @{
                NSWorkspaceLaunchConfigurationArguments: @[@"--config-file", config, @"start", @"--always-new-process", @"--no-auto-connect", @"--cwd", run],
                NSWorkspaceLaunchConfigurationEnvironment: env
            };
            NSError *error = nil;
            NSRunningApplication *app = [[NSWorkspace sharedWorkspace]
                launchApplicationAtURL:[NSURL fileURLWithPath:path]
                options:NSWorkspaceLaunchNewInstance | NSWorkspaceLaunchWithoutAddingToRecents
                configuration:configuration error:&error];
            if (!app || !owned(app, path)) {
                fprintf(stderr, "LaunchServices: %s\n", [[error description] UTF8String]);
                return 1;
            }
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            emit(@{@"pid": @([app processIdentifier]), @"bundle_id": [app bundleIdentifier], @"launch_services": @YES});
            return 0;
        }
        pid_t pid = process(argv[3]);
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if ([mode isEqualToString:@"status"]) {
            if (app && !owned(app, path)) { fprintf(stderr, "PID does not belong to this staged app\n"); return 1; }
            emit(@{@"running": @(app && ![app isTerminated])});
            return 0;
        }
        if (!owned(app, path) || [app isTerminated]) return 1;
        NSArray *list = windows(pid);
        if ([mode isEqualToString:@"windows"]) { emit(list); return 0; }
        if ([mode isEqualToString:@"capture"]) {
            if (argc != 6) return 2;
            CGWindowID identifier = (CGWindowID)process(argv[4]);
            BOOL found = NO;
            for (NSDictionary *window in list) if ([window[@"id"] unsignedIntValue] == identifier) found = YES;
            if (!found) { fprintf(stderr, "capture refused: window is not owned by this app\n"); return 1; }
            CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                identifier, kCGWindowImageBoundsIgnoreFraming);
            if (!image) return 1;
            NSURL *output = [NSURL fileURLWithPath:text(argv[5])];
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)output, kUTTypePNG, 1, NULL);
            if (!destination) { CGImageRelease(image); return 1; }
            CGImageDestinationAddImage(destination, image, NULL);
            BOOL ok = CGImageDestinationFinalize(destination);
            CFRelease(destination);
            CGImageRelease(image);
            return ok ? 0 : 1;
        }
        return 2;
    }
}
