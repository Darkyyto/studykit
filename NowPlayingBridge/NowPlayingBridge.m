#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef void (*GetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPIDFunction)(dispatch_queue_t, void (^)(int));
typedef void (*GetPlayingFunction)(dispatch_queue_t, void (^)(BOOL));
typedef void (*RegisterFunction)(dispatch_queue_t);
typedef Boolean (*SendCommandFunction)(int, NSDictionary *);
typedef void (*SetElapsedFunction)(double);

static void *MediaRemote(void) {
    static void *handle;
    if (!handle) {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    }
    return handle;
}

static NSString *Constant(const char *name) {
    NSString * __unsafe_unretained *value = (NSString * __unsafe_unretained *)dlsym(MediaRemote(), name);
    return value ? *value : [NSString stringWithUTF8String:name];
}

static void Write(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) {
        return;
    }
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void Emit(void) {
    GetPIDFunction getPID = dlsym(MediaRemote(), "MRMediaRemoteGetNowPlayingApplicationPID");
    GetInfoFunction getInfo = dlsym(MediaRemote(), "MRMediaRemoteGetNowPlayingInfo");
    GetPlayingFunction getPlaying = dlsym(MediaRemote(), "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getPID || !getInfo || !getPlaying) {
        return;
    }
    dispatch_queue_t queue = dispatch_get_main_queue();
    getPID(queue, ^(int pid) {
        getPlaying(queue, ^(BOOL playing) {
            getInfo(queue, ^(NSDictionary *info) {
                NSMutableDictionary *payload = [NSMutableDictionary dictionary];
                NSRunningApplication *app = pid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;
                payload[@"bundle"] = app.bundleIdentifier ?: @"";
                payload[@"app"] = app.localizedName ?: @"";
                payload[@"playing"] = @(playing);
                payload[@"title"] = info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
                payload[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                payload[@"duration"] = info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
                payload[@"elapsed"] = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0;
                NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                payload[@"timestamp"] = @((stamp ?: [NSDate date]).timeIntervalSince1970);
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([artwork isKindOfClass:[NSData class]] && artwork.length < 4000000) {
                    payload[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                }
                Write(payload);
            });
        });
    });
}

void FocusKitNowPlayingStream(void) {
    RegisterFunction registerForNotifications = dlsym(MediaRemote(), "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!registerForNotifications) {
        exit(2);
    }
    registerForNotifications(dispatch_get_main_queue());
    NSArray<NSString *> *names = @[
        Constant("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
        Constant("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
        Constant("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
    ];
    __block BOOL pending = NO;
    for (NSString *name in names) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if (pending) {
                return;
            }
            pending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                pending = NO;
                Emit();
            });
        }];
    }
    pid_t parent = getppid();
    dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(watchdog, ^{
        if (getppid() != parent) {
            exit(0);
        }
    });
    dispatch_resume(watchdog);
    Emit();
    CFRunLoopRun();
}

void FocusKitNowPlayingCommand(void) {
    const char *position = getenv("FOCUSKIT_POSITION");
    if (position) {
        SetElapsedFunction setElapsed = dlsym(MediaRemote(), "MRMediaRemoteSetElapsedTime");
        if (setElapsed) {
            setElapsed(atof(position));
        }
    } else {
        const char *command = getenv("FOCUSKIT_COMMAND");
        SendCommandFunction send = dlsym(MediaRemote(), "MRMediaRemoteSendCommand");
        if (send && command) {
            send(atoi(command), nil);
        }
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
}
