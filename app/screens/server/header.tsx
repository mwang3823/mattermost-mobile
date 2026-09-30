// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import {Image} from 'expo-image';
import React from 'react';
import {View} from 'react-native';

import FormattedText from '@components/formatted_text';
import {useIsTablet} from '@hooks/device';
import {changeOpacity, makeStyleSheetFromTheme} from '@utils/theme';
import {typography} from '@utils/typography';

const brandLogo = require('@assets/images/tdc_logo.png');

const LOGO_SIZE = 96;

type Props = {
    additionalServer: boolean;
    theme: Theme;
};

const getStyleSheet = makeStyleSheetFromTheme((theme: Theme) => ({
    logo: {
        width: LOGO_SIZE,
        height: LOGO_SIZE,
        marginBottom: 8,
    },
    textContainer: {
        marginBottom: 32,
        maxWidth: 600,
        width: '100%',
        paddingHorizontal: 20,
    },
    welcome: {
        marginTop: 12,
        color: changeOpacity(theme.centerChannelColor, 0.64),
        ...typography('Heading', 400, 'SemiBold'),
    },
    connect: {
        width: 300,
        letterSpacing: -1,
        color: theme.centerChannelColor,
        marginVertical: 12,
        ...typography('Heading', 1000, 'SemiBold'),
    },
    connectTablet: {
        width: undefined,
    },
    description: {
        color: changeOpacity(theme.centerChannelColor, 0.64),
        ...typography('Body', 200, 'Regular'),
    },
}));

const ServerHeader = ({additionalServer, theme}: Props) => {
    const isTablet = useIsTablet();
    const styles = getStyleSheet(theme);

    let title;
    if (additionalServer) {
        title = (
            <FormattedText
                defaultMessage='Add a server'
                id='servers.create_button'
                style={[styles.connect, isTablet ? styles.connectTablet : undefined]}
                testID='server_header.title.add_server'
            />
        );
    } else {
        title = (
            <FormattedText
                defaultMessage='Let’s Connect to a Server'
                id='mobile.components.select_server_view.msg_connect'
                style={[styles.connect, isTablet ? styles.connectTablet : undefined]}
                testID='server_header.title.connect_to_server'
            />
        );
    }

    return (
        <View style={styles.textContainer}>
            <Image
                source={brandLogo}
                style={styles.logo}
                contentFit='contain'
                testID='server_header.logo'
            />
            {!additionalServer &&
            <FormattedText
                defaultMessage='Welcome'
                id='mobile.components.select_server_view.msg_welcome'
                testID='server_header.welcome'
                style={styles.welcome}
            />
            }
            {title}
            <FormattedText
                defaultMessage="A server is your team's communication hub accessed using a unique URL"
                id='mobile.components.select_server_view.msg_description'
                style={styles.description}
                testID='server_header.description'
            />
        </View>
    );
};

export default ServerHeader;
