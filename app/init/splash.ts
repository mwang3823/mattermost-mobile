// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import * as SplashScreen from 'expo-splash-screen';

let claimed = false;

/**
 * The initial route claims the splash screen so it remains visible while the launch flow
 * resolves where to navigate, which includes connecting to the server when the app is pinned
 * to a single one. Launches that never render that route fall back to the root layout hiding
 * the splash screen as soon as the app is ready.
 */
export function claimSplashScreen() {
    claimed = true;
}

export function isSplashScreenClaimed() {
    return claimed;
}

export function hideSplashScreen() {
    claimed = false;
    SplashScreen.hideAsync();
}
