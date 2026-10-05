// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import React from 'react';
import {defineMessages, useIntl} from 'react-intl';
import {Text, View} from 'react-native';

import Button from '@components/button';
import CompassIcon from '@components/compass_icon';
import FormattedText from '@components/formatted_text';
import Loading from '@components/loading';
import {changeOpacity, makeStyleSheetFromTheme} from '@utils/theme';
import {typography} from '@utils/typography';

type Props = {
    attempted: boolean;
    connecting: boolean;
    error?: string;
    onRetry: () => void;
    theme: Theme;
};

const getStyleSheet = makeStyleSheetFromTheme((theme: Theme) => ({
    container: {
        alignItems: 'center',
        maxWidth: 600,
        width: '100%',
        paddingHorizontal: 24,
        gap: 12,
    },
    title: {
        color: theme.centerChannelColor,
        textAlign: 'center',
        ...typography('Heading', 400, 'SemiBold'),
    },
    description: {
        color: changeOpacity(theme.centerChannelColor, 0.64),
        textAlign: 'center',
        ...typography('Body', 200, 'Regular'),
    },
    errorDetail: {
        color: theme.errorTextColor,
        textAlign: 'center',
        ...typography('Body', 75, 'Regular'),
    },
    buttonContainer: {
        width: '100%',
        marginTop: 20,
    },
}));

const messages = defineMessages({
    connecting: {
        id: 'mobile.server.connection_status.connecting',
        defaultMessage: 'Connecting to the server…',
    },
    connectingDescription: {
        id: 'mobile.server.connection_status.connecting_description',
        defaultMessage: 'Please wait a moment.',
    },
    failedTitle: {
        id: 'mobile.server.connection_status.failed_title',
        defaultMessage: 'Unable to connect to the server',
    },
    failedDescription: {
        id: 'mobile.server.connection_status.failed_description',
        defaultMessage: 'Please check your internet connection and try again.',
    },
    connect: {
        id: 'mobile.server.connection_status.connect',
        defaultMessage: 'Connect',
    },
    retry: {
        id: 'mobile.server.connection_status.retry',
        defaultMessage: 'Try again',
    },
});

const ServerConnectionStatus = ({attempted, connecting, error, onRetry, theme}: Props) => {
    const {formatMessage} = useIntl();
    const styles = getStyleSheet(theme);

    if (connecting || (!attempted && !error)) {
        return (
            <View
                style={styles.container}
                testID='server_connection_status.connecting'
            >
                <Loading
                    size='large'
                    themeColor='buttonBg'
                />
                <FormattedText
                    {...messages.connecting}
                    style={styles.title}
                />
                <FormattedText
                    {...messages.connectingDescription}
                    style={styles.description}
                />
            </View>
        );
    }

    if (!error) {
        return (
            <View
                style={styles.container}
                testID='server_connection_status.idle'
            >
                <View style={styles.buttonContainer}>
                    <Button
                        onPress={onRetry}
                        testID='server_connection_status.connect.button'
                        size='lg'
                        theme={theme}
                        text={formatMessage(messages.connect)}
                    />
                </View>
            </View>
        );
    }

    return (
        <View
            style={styles.container}
            testID='server_connection_status.failed'
        >
            <CompassIcon
                name='alert-circle-outline'
                size={48}
                color={theme.errorTextColor}
            />
            <FormattedText
                {...messages.failedTitle}
                style={styles.title}
            />
            <FormattedText
                {...messages.failedDescription}
                style={styles.description}
            />
            <Text
                style={styles.errorDetail}
                testID='server_connection_status.error'
            >
                {error}
            </Text>
            <View style={styles.buttonContainer}>
                <Button
                    onPress={onRetry}
                    testID='server_connection_status.retry.button'
                    size='lg'
                    theme={theme}
                    text={formatMessage(messages.retry)}
                />
            </View>
        </View>
    );
};

export default ServerConnectionStatus;
