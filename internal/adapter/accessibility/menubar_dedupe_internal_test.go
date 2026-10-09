package accessibility

import (
	"image"
	"testing"

	"github.com/y3owk1n/neru/internal/domain/element"
)

func TestDedupeByBounds_DropsSecondHintOnSameIcon(t *testing.T) {
	icon := image.Rect(100, 0, 120, 24)
	other := image.Rect(130, 0, 150, 24)

	var elements []*element.Element

	for i, bounds := range []image.Rectangle{icon, other, icon} {
		elem, err := element.NewElement(element.ID(rune('a'+i)), bounds, element.RoleMenuBarItem)
		if err != nil {
			t.Fatalf("NewElement() error: %v", err)
		}

		elements = append(elements, elem)
	}

	kept := dedupeByBounds(elements)
	if len(kept) != 2 || kept[0].Bounds() != icon || kept[1].Bounds() != other {
		t.Fatalf("dedupeByBounds() kept %d elements, want the icon and the other once each", len(kept))
	}
}
