//
//  accessibility_window.m
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#import "accessibility.h"
#import "accessibility_visibility.h"

#import <Cocoa/Cocoa.h>

#pragma mark - Focus Functions

/// Set focus to element
/// @param element Element reference
/// @return 1 on success, 0 on failure
int NeruSetFocus(void *element) {
	if (!element)
		return 0;

	AXUIElementRef axElement = (AXUIElementRef)element;
	CFBooleanRef trueValue = kCFBooleanTrue;
	AXError error = AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute, trueValue);

	return (error == kAXErrorSuccess) ? 1 : 0;
}

#pragma mark - Window Functions

/// Run work here, or on the main thread when element belongs to this process
/// and we are off it. Our own app answers accessibility questions on the asking
/// thread, running its AppKit and SwiftUI code there (Element.isOwn in Go).
static void onMainIfOwn(AXUIElementRef element, void (^work)(void)) {
	if (![NSThread isMainThread] && NeruIsOwnElement((void *)element)) {
		dispatch_sync(dispatch_get_main_queue(), work);
		return;
	}
	work();
}

/// Windows of an application
/// @param app Borrowed application reference
/// @param count Output parameter for number of windows, left alone on failure
/// @return Array of window references
static void **copyAllWindows(AXUIElementRef app, int *count) {
	@autoreleasepool {
		CFTypeRef windowsValue = NULL;
		if (AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windowsValue) != kAXErrorSuccess)
			return NULL;

		if (CFGetTypeID(windowsValue) != CFArrayGetTypeID()) {
			CFRelease(windowsValue);
			return NULL;
		}

		CFArrayRef windows = (CFArrayRef)windowsValue;
		CFIndex windowCount = CFArrayGetCount(windows);

		void **result = (void **)malloc(windowCount * sizeof(void *));
		if (!result) {
			CFRelease(windowsValue);
			return NULL;
		}

		for (CFIndex i = 0; i < windowCount; i++) {
			AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
			CFRetain(window);
			result[i] = (void *)window;
		}

		*count = (int)windowCount;
		CFRelease(windowsValue);
		return result;
	}
}

/// Get all windows of focused application
/// @param count Output parameter for number of windows
/// @return Array of window references
void **NeruGetAllWindows(int *count) {
	if (!count)
		return NULL;

	*count = 0;

	AXUIElementRef app = (AXUIElementRef)NeruGetFocusedApplication();
	if (!app)
		return NULL;

	__block void **result = NULL;
	onMainIfOwn(app, ^{
		result = copyAllWindows(app, count);
	});
	CFRelease(app);
	return result;
}

/// Focused window plus popover windows of an application
/// @param app Borrowed application reference
/// @param count Output parameter for number of returned windows, set to 0 first
/// @return Array of retained window references
static void **copyFrontmostAndPopoverWindows(AXUIElementRef app, int *count) {
	@autoreleasepool {
		// Batch fetch focused window and all windows in a single AX call
		CFArrayRef windowAttrs = CFArrayCreate(
		    NULL,
		    (CFTypeRef[]){
		        kAXFocusedWindowAttribute,
		        kAXWindowsAttribute,
		    },
		    2, &kCFTypeArrayCallBacks);
		if (!windowAttrs)
			return NULL;

		CFArrayRef windowValues = NULL;
		AXError batchError = AXUIElementCopyMultipleAttributeValues(app, windowAttrs, 0, &windowValues);
		CFRelease(windowAttrs);

		AXUIElementRef focusedWindow = NULL;
		CFTypeRef windowsValue = NULL;
		CFArrayRef windows = NULL;
		CFIndex windowCount = 0;

		if (batchError == kAXErrorSuccess && windowValues && CFArrayGetCount(windowValues) >= 2) {
			CFTypeRef focusedVal = (CFTypeRef)CFArrayGetValueAtIndex(windowValues, 0);
			if (focusedVal && CFGetTypeID(focusedVal) != CFNullGetTypeID()) {
				focusedWindow = (AXUIElementRef)focusedVal;
				CFRetain(focusedWindow);
			}

			CFTypeRef windowsVal = (CFTypeRef)CFArrayGetValueAtIndex(windowValues, 1);
			if (windowsVal && CFGetTypeID(windowsVal) == CFArrayGetTypeID()) {
				windowsValue = windowsVal;
				CFRetain(windowsValue);
				windows = (CFArrayRef)windowsValue;
				windowCount = CFArrayGetCount(windows);
			}
		}

		if (windowValues)
			CFRelease(windowValues);

		CFIndex capacity = (focusedWindow ? 1 : 0) + windowCount;
		void **result = capacity ? (void **)malloc(capacity * sizeof(void *)) : NULL;
		if (!result) {
			if (windowsValue)
				CFRelease(windowsValue);
			if (focusedWindow)
				CFRelease(focusedWindow);
			return NULL;
		}

		if (focusedWindow) {
			result[*count] = (void *)focusedWindow;
			(*count)++;
		} else if (windowCount > 0) {
			AXUIElementRef firstWindow = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 0);
			if (firstWindow) {
				CFRetain(firstWindow);
				result[*count] = (void *)firstWindow;
				(*count)++;
			}
		}

		for (CFIndex i = 0; i < windowCount; i++) {
			AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
			if (!window)
				continue;

			if (focusedWindow && CFEqual(window, focusedWindow))
				continue;
			if (!focusedWindow && i == 0)
				continue;

			CFTypeRef roleValue = NULL;
			if (AXUIElementCopyAttributeValue(window, kAXRoleAttribute, &roleValue) != kAXErrorSuccess || !roleValue) {
				if (roleValue)
					CFRelease(roleValue);
				continue;
			}

			bool isPopover = CFGetTypeID(roleValue) == CFStringGetTypeID() &&
			                 CFStringCompare((CFStringRef)roleValue, CFSTR("AXPopover"), 0) == kCFCompareEqualTo;
			CFRelease(roleValue);

			if (!isPopover)
				continue;

			CFRetain(window);
			result[*count] = (void *)window;
			(*count)++;
		}

		if (windowsValue)
			CFRelease(windowsValue);

		if (*count == 0) {
			free(result);
			return NULL;
		}

		return result;
	}
}

/// Get focused window plus popover windows of the focused application.
/// This keeps hint activation on one focused-app lookup and avoids asking Go
/// to fetch each window role separately just to discover AXPopover siblings.
void **NeruGetFrontmostAndPopoverWindows(int *count) {
	if (!count)
		return NULL;

	*count = 0;

	AXUIElementRef app = (AXUIElementRef)NeruGetFocusedApplication();
	if (!app)
		return NULL;

	__block void **result = NULL;
	onMainIfOwn(app, ^{
		result = copyFrontmostAndPopoverWindows(app, count);
	});
	CFRelease(app);
	return result;
}

/// Focused window of an application, or its first window
/// @param app Borrowed application reference
/// @return Window reference
static void *copyFrontmostWindow(AXUIElementRef app) {
	@autoreleasepool {
		// Batch fetch focused window and all windows in a single AX call
		CFArrayRef windowAttrs = CFArrayCreate(
		    NULL,
		    (CFTypeRef[]){
		        kAXFocusedWindowAttribute,
		        kAXWindowsAttribute,
		    },
		    2, &kCFTypeArrayCallBacks);
		if (!windowAttrs)
			return NULL;

		CFArrayRef windowValues = NULL;
		AXError batchError = AXUIElementCopyMultipleAttributeValues(app, windowAttrs, 0, &windowValues);
		CFRelease(windowAttrs);

		AXUIElementRef window = NULL;
		CFArrayRef windows = NULL;

		if (batchError == kAXErrorSuccess && windowValues && CFArrayGetCount(windowValues) >= 2) {
			CFTypeRef focusedVal = (CFTypeRef)CFArrayGetValueAtIndex(windowValues, 0);
			if (focusedVal && CFGetTypeID(focusedVal) != CFNullGetTypeID()) {
				window = (AXUIElementRef)focusedVal;
				CFRetain(window);
			}

			CFTypeRef windowsVal = (CFTypeRef)CFArrayGetValueAtIndex(windowValues, 1);
			if (windowsVal && CFGetTypeID(windowsVal) == CFArrayGetTypeID()) {
				windows = (CFArrayRef)windowsVal;
				CFRetain(windows);
			}
		}

		if (windowValues)
			CFRelease(windowValues);

		// Fallback: use first window from the windows list
		if (!window && windows && CFArrayGetCount(windows) > 0) {
			window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 0);
			CFRetain(window);
		}

		if (windows)
			CFRelease(windows);

		return (void *)window;
	}
}

/// Get frontmost window
/// @return Frontmost window reference
void *NeruGetFrontmostWindow(void) {
	AXUIElementRef app = (AXUIElementRef)NeruGetFocusedApplication();
	if (!app)
		return NULL;

	__block void *result = NULL;
	onMainIfOwn(app, ^{
		result = copyFrontmostWindow(app);
	});
	CFRelease(app);
	return result;
}

/// Frame (position + size) of a window
/// @param window Borrowed window reference
/// @return Window frame rectangle, or CGRectZero when it cannot be read
static CGRect windowFrame(AXUIElementRef window) {
	@autoreleasepool {
		CFArrayRef attributes = CFArrayCreate(
		    NULL,
		    (const void **)(CFTypeRef[]){
		        kAXPositionAttribute,
		        kAXSizeAttribute,
		    },
		    2, &kCFTypeArrayCallBacks);

		if (!attributes)
			return CGRectZero;

		CFArrayRef values = NULL;
		AXError error = AXUIElementCopyMultipleAttributeValues(window, attributes, 0, &values);
		CFRelease(attributes);

		if (error != kAXErrorSuccess || !values) {
			if (values)
				CFRelease(values);
			return CGRectZero;
		}

		CGRect frame = CGRectZero;
		CFIndex count = CFArrayGetCount(values);

		if (count > 0) {
			CFTypeRef positionValue = (CFTypeRef)CFArrayGetValueAtIndex(values, 0);
			if (positionValue && CFGetTypeID(positionValue) == AXValueGetTypeID()) {
				CGPoint point;
				if (AXValueGetValue((AXValueRef)positionValue, kAXValueCGPointType, &point)) {
					frame.origin = point;
				}
			}
		}

		if (count > 1) {
			CFTypeRef sizeValue = (CFTypeRef)CFArrayGetValueAtIndex(values, 1);
			if (sizeValue && CFGetTypeID(sizeValue) == AXValueGetTypeID()) {
				CGSize size;
				if (AXValueGetValue((AXValueRef)sizeValue, kAXValueCGSizeType, &size)) {
					frame.size = size;
				}
			}
		}

		CFRelease(values);
		return frame;
	}
}

/// Get the frame (position + size) of the focused window
/// @return Window frame rectangle, or CGRectZero if no window is found
CGRect NeruGetFocusedWindowFrame(void) {
	AXUIElementRef window = (AXUIElementRef)NeruGetFrontmostWindow();
	if (!window)
		return CGRectZero;

	__block CGRect result = CGRectZero;
	onMainIfOwn(window, ^{
		result = windowFrame(window);
	});
	CFRelease(window);
	return result;
}

/// Get application name
/// @param app Application reference
/// @return Application name string
char *NeruGetApplicationName(void *app) {
	if (!app)
		return NULL;

	AXUIElementRef axApp = (AXUIElementRef)app;
	CFTypeRef titleValue = NULL;

	if (AXUIElementCopyAttributeValue(axApp, kAXTitleAttribute, &titleValue) != kAXErrorSuccess) {
		return NULL;
	}

	char *result = NULL;
	if (CFGetTypeID(titleValue) == CFStringGetTypeID()) {
		result = NeruCFStringToCString((CFStringRef)titleValue);
	}

	CFRelease(titleValue);
	return result;
}

/// Get bundle identifier
/// @param app Application reference
/// @return Bundle identifier string
char *NeruGetBundleIdentifier(void *app) {
	if (!app)
		return NULL;

	@autoreleasepool {
		pid_t pid;
		if (AXUIElementGetPid((AXUIElementRef)app, &pid) != kAXErrorSuccess) {
			return NULL;
		}

		NSRunningApplication *runningApp = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
		if (!runningApp)
			return NULL;

		NSString *bundleId = [runningApp bundleIdentifier];
		if (!bundleId)
			return NULL;

		return NeruCFStringToCString((__bridge CFStringRef)bundleId);
	}
}

/// Get bundle identifier from PID directly
/// @param pid Process identifier
/// @return Bundle identifier string, or NULL if not found
char *NeruGetBundleIDForPID(int pid) {
	@autoreleasepool {
		NSRunningApplication *runningApp = [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pid];
		if (!runningApp)
			return NULL;

		NSString *bundleId = [runningApp bundleIdentifier];
		if (!bundleId)
			return NULL;

		return NeruCFStringToCString((__bridge CFStringRef)bundleId);
	}
}
