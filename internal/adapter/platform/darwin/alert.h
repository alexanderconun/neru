//
//  alert.h
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#ifndef ALERT_H
#define ALERT_H

#import <Foundation/Foundation.h>

/// The name the native dialogs call the app: the bundle's CFBundleDisplayName,
/// so a rebranded build names itself, else "Neru" (bare binary, or no key).
static inline NSString *NeruAppName(void) {
	id name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	return [name isKindOfClass:[NSString class]] && [name length] > 0 ? name : @"Neru";
}

#pragma mark - Alert Functions

/// Show a config validation error alert with error details and config path
/// @param errorMessage The error message to display
/// @param configPath The path to the config file
/// @return 1 if user clicked OK, 2 if user clicked Copy Path, 0 otherwise
int NeruShowConfigValidationErrorAlert(const char *errorMessage, const char *configPath);

/// Show a config onboarding alert for new users
/// @param configPath The default config path that will be created
/// @return 1 if user clicked Create Config, 2 if user clicked Use Defaults, 3 if user clicked Quit
int NeruShowConfigOnboardingAlert(const char *configPath);

/// Show the startup accessibility permission guidance alert.
/// The alert lets the user request permission, and closes on its own once it is granted.
/// @return 1 if permission is granted, 2 if the user chose Quit.
int NeruShowAccessibilityPermissionStartupAlert(void);

/// Show a macOS notification with a title and message.
/// Uses UNUserNotificationCenter when running as an app bundle, logs to console otherwise.
/// @note This function is asynchronous — it returns immediately before the
///       notification is delivered. Callers must not depend on the notification
///       being visible when this function returns.
/// @param title The notification title
/// @param message The notification message
void NeruShowNotification(const char *title, const char *message);

#endif /* ALERT_H */
