//go:build darwin

package darwin

/*
#include "sound.h"
*/
import "C"

// playSound queues a feedback sound on the main queue and returns at once.
// kind is a ports.Sound value, which sound.h numbers the same way.
func playSound(kind int, volume float64) {
	C.NeruPlaySound(C.int(kind), C.double(volume))
}
