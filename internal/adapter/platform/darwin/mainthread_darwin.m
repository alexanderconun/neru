//
//  mainthread_darwin.m
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#import "mainthread.h"

#import <Foundation/Foundation.h>

extern void neruRunGoHandle(uintptr_t handle);

void NeruRunOnMainThread(uintptr_t handle) {
	if ([NSThread isMainThread]) {
		neruRunGoHandle(handle);
		return;
	}
	dispatch_sync(dispatch_get_main_queue(), ^{
		neruRunGoHandle(handle);
	});
}
