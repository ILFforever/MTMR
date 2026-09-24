//
//  NowPlayingHelper.m
//  Stripe
//
//  Reports whether media is playing, system-wide. Since macOS 15.4 MediaRemote
//  only answers Apple-signed processes, so this library isn't loaded into Stripe:
//  NowPlaying.swift runs it inside /usr/bin/perl, which loads it and calls
//  stripe_now_playing_run().
//
//  Prints "playing 1" or "playing 0" on stdout whenever that changes, and exits
//  when stdin closes (i.e. when Stripe quits).
//

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*IsPlayingFn)(dispatch_queue_t, void (^)(Boolean));

__attribute__((visibility("default"))) void stripe_now_playing_run(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    RegisterFn registerForNotifications = mr ? (RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    IsPlayingFn isPlaying = mr ? (IsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    if (!isPlaying) {
        fprintf(stderr, "Stripe now playing: MediaRemote unavailable\n");
        exit(1);
    }

    dispatch_queue_t queue = dispatch_get_main_queue();
    __block int last = -1;
    void (^report)(void) = ^{
        isPlaying(queue, ^(Boolean playing) {
            if (playing != last) {
                last = playing;
                printf("playing %d\n", playing ? 1 : 0);
                fflush(stdout);
            }
        });
    };

    if (registerForNotifications) registerForNotifications(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingInfoDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                      usingBlock:^(NSNotification *note) { report(); }];
    }

    // In case a change arrives without a notification.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 3 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, report);
    dispatch_resume(timer);

    // Stripe holds our stdin open; end of input means it quit.
    dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    dispatch_source_set_event_handler(input, ^{
        char buffer[64];
        if (read(STDIN_FILENO, buffer, sizeof buffer) <= 0) exit(0);
    });
    dispatch_resume(input);

    dispatch_main();
}
