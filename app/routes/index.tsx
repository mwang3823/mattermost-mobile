// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import {Redirect, type Href} from 'expo-router';
import {useEffect, useState} from 'react';
import {useIntl} from 'react-intl';

import useDidMount from '@hooks/did_mount';
import {determineInitialExpoRoute, type ExpoRouterLaunchResult} from '@init/launch';
import {claimSplashScreen, hideSplashScreen} from '@init/splash';
import {logError} from '@utils/log';
import {canReceiveNotifications} from '@utils/push_proxy';

// Delay used to let the navigation to the destination screen settle before presenting the
// push proxy alert, so it is never rendered on top of the splash screen.
const PUSH_PROXY_ALERT_DELAY = 1000;

export default function RootIndex() {
    const intl = useIntl();
    const [launchResult, setLaunchResult] = useState<ExpoRouterLaunchResult | null>(null);

    useDidMount(() => {
        claimSplashScreen();
    });

    useEffect(() => {
        async function initializeLaunch() {
            try {
                const result = await determineInitialExpoRoute();
                setLaunchResult(result);
            } catch (error) {
                logError('error on RootIndex.initializeLaunch', error);
                setLaunchResult({route: '/(unauthenticated)/server', params: {}});
            }
        }

        initializeLaunch();
    }, []);

    // The splash screen stays visible until the initial route is known, so the connection to the
    // server happens behind it instead of on an intermediate screen.
    useEffect(() => {
        if (!launchResult) {
            return undefined;
        }

        hideSplashScreen();

        const pushProxy = launchResult.pushProxy;
        if (!pushProxy) {
            return undefined;
        }

        const timeout = setTimeout(() => {
            canReceiveNotifications(pushProxy.serverUrl, pushProxy.verification, intl);
        }, PUSH_PROXY_ALERT_DELAY);

        return () => clearTimeout(timeout);
    }, [launchResult, intl]);

    if (!launchResult) {
        return null; // Still determining initial route
    }

    // Redirect to the determined route with params
    const href: Href = {pathname: launchResult.route, params: launchResult.params};
    return <Redirect href={href}/>;
}
