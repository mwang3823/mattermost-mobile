// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

// Moi truong server (prod/dev...) khai bao o Build.Environments trong config.json.
// Build.Environment chon moi truong mac dinh; bien moi truong TDC_ENV ghi de khi build.
// Gia tri cua moi truong duoc tron vao config app (dist/assets/config.json).

'use strict';

function selectedEnv(json) {
    // eslint-disable-next-line no-process-env
    return process.env.TDC_ENV || (json.Build && json.Build.Environment) || '';
}

// config.json -> config app: tron moi truong dang chon roi bo khoi "Build"
function toAppConfig(json) {
    const out = Object.assign({}, json);
    const name = selectedEnv(json);
    const envs = (json.Build && json.Build.Environments) || {};
    delete out.Build;
    if (name) {
        if (!envs[name]) {
            throw new Error(`môi trường "${name}" không có trong Build.Environments (${Object.keys(envs).join(', ')})`);
        }
        Object.assign(out, envs[name]);
    }
    return out;
}

module.exports = {selectedEnv, toAppConfig};
