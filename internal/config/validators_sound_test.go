package config_test

import (
	"testing"

	"github.com/y3owk1n/neru/internal/config"
)

func TestConfig_ValidateSound_RejectsVolumeOutsideZeroToHundred(t *testing.T) {
	tests := []struct {
		volume int
		valid  bool
	}{
		{-1, false},
		{0, true},
		{config.DefaultSoundVolume, true},
		{100, true},
		{101, false},
	}

	for _, testCase := range tests {
		cfg := config.DefaultConfig()
		cfg.Sound.Volume = testCase.volume

		err := cfg.ValidateSound()
		if (err == nil) != testCase.valid {
			t.Errorf("ValidateSound() with volume %d: err = %v, want valid = %v",
				testCase.volume, err, testCase.valid)
		}
	}
}
