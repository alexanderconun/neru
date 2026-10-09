//
//  sound.h
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#ifndef SOUND_H
#define SOUND_H

#import <Foundation/Foundation.h>

#pragma mark - Feedback Sounds

/// Play a feedback sound. The work is queued on the main queue and the call
/// returns at once, because callers may hold the mode handler's lock. A sound
/// already playing restarts.
/// @param kind 0 = click, 1 = warning (the values of ports.Sound)
/// @param volume 0..1
void NeruPlaySound(int kind, double volume);

#endif /* SOUND_H */
