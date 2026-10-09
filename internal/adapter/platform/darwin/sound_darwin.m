//
//  sound_darwin.m
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#import "sound.h"

#import <Cocoa/Cocoa.h>

#pragma mark - Feedback Sounds

/// Tink is short and high, which reads as a tap. Basso is low and under a
/// second (Funk rings for two), so it reads as "no" without lingering past the
/// next action, and the two can never be confused.
void NeruPlaySound(int kind, double volume) {
	// dispatch_async only: the caller may hold the mode handler's lock, so this
	// must neither wait on the main queue nor call back into Go.
	dispatch_async(dispatch_get_main_queue(), ^{
		// soundNamed: hands back one cached instance per name, and play on an
		// instance that is still playing does nothing. Stop it first so a rapid
		// second click restarts the sound instead of losing it.
		NSSound *sound = [NSSound soundNamed:kind == 1 ? @"Basso" : @"Tink"];
		[sound stop];
		sound.volume = (float)volume;
		[sound play];
	});
}
