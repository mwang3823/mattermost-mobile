// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import {doPing} from '@actions/remote/general';
import {fetchConfigAndLicense} from '@actions/remote/systems';
import LocalConfig from '@assets/config.json';
import {Launch, Screens} from '@constants';
import {getServerCredentials} from '@init/credentials';
import SecurityManager from '@managers/security_manager';
import {getServerByIdentifier} from '@queries/app/servers';
import {getExpoRouterPath} from '@screens/navigation';
import {logDebug} from '@utils/log';
import {loginOptions} from '@utils/server';
import {getServerUrlAfterRedirect} from '@utils/url';

import type {ExpoRouterLaunchResult} from './launch';
import type {LaunchProps} from '@typings/launch';

/**
 * The server screen is skipped entirely when the app is pinned to a single server
 * (AutoSelectServerUrl + DefaultServerUrl + DefaultServerName). Adding another server
 * from inside the app still goes through the server screen.
 */
export function canAutoConnect(props: LaunchProps) {
    return Boolean(
        LocalConfig.AutoSelectServerUrl &&
        LocalConfig.DefaultServerUrl &&
        LocalConfig.DefaultServerName &&
        props.launchType !== Launch.AddServer &&
        props.launchType !== Launch.AddServerFromDeepLink,
    );
}

const toParams = (props: Record<string, unknown>): Record<string, string> => {
    return Object.keys(props).reduce((params, key) => {
        if (props[key] !== undefined) {
            params[key] = JSON.stringify(props[key]);
        }
        return params;
    }, {} as Record<string, string>);
};

/**
 * Performs the same connection sequence as the server screen (redirect resolution, ping,
 * config & license fetch and the security gates) without rendering it, so the app can go
 * from the splash screen straight to the login screen.
 *
 * Returns undefined when the server cannot be reached or any gate fails, in which case the
 * caller falls back to the server screen so the user can fix the connection manually.
 */
export async function autoConnectToDefaultServer(props: LaunchProps, theme: Theme): Promise<ExpoRouterLaunchResult | undefined> {
    const displayName = LocalConfig.DefaultServerName;

    // sanitizeUrl upgrades http to https unless told otherwise; keep http for servers
    // configured that way (e.g. the dev environment).
    const useHttp = LocalConfig.DefaultServerUrl.startsWith('http://');
    const headRequest = await getServerUrlAfterRedirect(LocalConfig.DefaultServerUrl, useHttp);
    if (!headRequest.url) {
        logDebug('autoConnectToDefaultServer: unable to resolve the server url');
        return undefined;
    }

    const serverUrl = headRequest.url;
    const ping = await doPing(serverUrl, true);
    if (ping.error) {
        logDebug('autoConnectToDefaultServer: ping failed');
        return undefined;
    }

    const data = await fetchConfigAndLicense(serverUrl, true);
    if (data.error || !data.config?.DiagnosticId) {
        logDebug('autoConnectToDefaultServer: unable to fetch the server configuration');
        return undefined;
    }

    if (data.config.MobileJailbreakProtection === 'true') {
        const isJailbroken = await SecurityManager.isDeviceJailbroken(serverUrl, data.config.SiteName);
        if (isJailbroken) {
            return undefined;
        }
    }

    if (data.config.MobileEnableBiometrics === 'true') {
        const authenticated = await SecurityManager.authenticateWithBiometrics(serverUrl, data.config.SiteName);
        if (!authenticated) {
            return undefined;
        }
    }

    const server = await getServerByIdentifier(data.config.DiagnosticId);
    const credentials = await getServerCredentials(serverUrl);
    if (server && server.lastActiveAt > 0 && credentials?.token) {
        logDebug('autoConnectToDefaultServer: the server is already connected');
        return undefined;
    }

    const {enabledSSOs, hasLoginForm, numberSSOs, ssoOptions} = loginOptions(data.config, data.license!);
    const redirectSSO = !hasLoginForm && numberSSOs === 1;

    return {
        route: getExpoRouterPath(redirectSSO ? Screens.SSO : Screens.LOGIN)!,
        params: toParams({
            ...props,
            config: data.config,
            hasLoginForm,
            license: data.license,
            serverDisplayName: displayName,
            serverUrl,
            ssoOptions,
            ssoType: redirectSSO ? enabledSSOs[0] : undefined,
            theme,
        }),
        pushProxy: {serverUrl, verification: ping.canReceiveNotifications as string},
    };
}
