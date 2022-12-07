// Template for the ArgoCD sync job to manage the OpenShift cluster pull
// secret.
// The job is modelled after the instructions outlined in
// https://docs.openshift.com/container-platform/4.11/post_installation_configuration/cluster-tasks.html#images-update-global-pull-secret_post-install-cluster-tasks
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_config;

// Jobs need get,update,patch for secret pull-secret in namespace openshift-config
// To ensure the unmanage job has the RBAC in place, all the RBAC objects are
// also in sync-wave -10.
local jobSA = kube.ServiceAccount('syn-cluster-pull-secret-manager') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-10',
    },
    namespace: 'openshift-config',
  },
};
local jobRole = kube.Role('syn-cluster-pull-secret-manager') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-10',
    },
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'update', 'patch' ],
      resourceNames: [ 'pull-secret' ],
    },
  ],
};
local jobRoleBinding = kube.RoleBinding('syn-cluster-pull-secret-manager') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-10',
    },
  },
  roleRef_: jobRole,
  subjects_: [ jobSA ],
};

local cleanJob = kube.Job('syn-unmanage-cluster-pull-secret') {
  metadata+: {
    annotations+: {
      // run before the default sync wave, but after creating the Job RBAC so
      // that we unmanage the cluster pull secret before patching it.
      'argocd.argoproj.io/sync-wave': '-9',
      'argocd.argoproj.io/hook': 'Sync',
      'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
    },
  },
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: jobSA.metadata.name,
        containers_: {
          clean: {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.kubectl,
            command: [
              'bash',
              '-c',
              'kubectl label secret pull-secret argocd.argoproj.io/instance-;' +
              'kubectl annotate secret pull-secret kubectl.kubernetes.io/last-applied-configuration-;' +
              'kubectl annotate secret pull-secret argocd.argoproj.io/sync-options-;',
            ],
          },
        },
      },
    },
  },
};

local syncScript = kube.Secret('syn-update-cluster-pull-secret-script') {
  stringData: {
    // The shell script reads the secret `pull-secret`, base64-decodes the
    // value of `.dockerconfigjson`, processes it with jq and updates the
    // secret with the result of the JQ script (see below).
    'sync-secret.sh': |||
      #!/bin/bash

      pull_secret=$(
          kubectl get secret pull-secret \
          -o go-template='{{index .data ".dockerconfigjson"|base64decode}}'
      )
      patched_secret=$(
        jq -cr '%(script)s' <<<"${pull_secret}"
      )
      kubectl -n openshift-config patch secret pull-secret \
        -p "{\"data\": {\".dockerconfigjson\": \"$patched_secret\"}}"
    ||| % {
      // We generate a JQ script which processes the pull-secret contents from
      // params.globalPullSecrets. For each entry in the parameter, we
      // generate a `.auths.[key]=[value]`. Jsonnet string formatting
      // automatically formats objects as valid JSON when formatting them with
      // %s. After processing each entry of the parameter, the script runs
      // `del(..|nulls)` to drop any keys with `null` values and `@base64` to
      // base64-encode the resulting object.
      script:
        // We transform the globalPullSecrets object into a list of objects
        // representing the entries of the object...
        local pullSecretKV = [
          {
            key: k,
            value: params.globalPullSecrets[k],
          }
          for k in std.objectFields(params.globalPullSecrets)
        ];
        // We use the transformed parameter to generate `.auths."[key]"=value`
        // for each entry...
        local auth_patches = std.foldl(function(str, cfg) str + '.auths."%(key)s"=%(value)s |' % cfg, pullSecretKV, '');
        // and finally we append `del(..|nulls)|@base64` to the script.
        auth_patches + 'del(..|nulls)|@base64',
    },
  },
};

local syncJob = kube.Job('syn-update-cluster-pull-secret') {
  metadata+: {
    annotations+: {
      // run after the default sync wave since we depend on the script secret.
      'argocd.argoproj.io/sync-wave': '10',
      'argocd.argoproj.io/hook': 'Sync',
      'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
    },
  },
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: jobSA.metadata.name,
        containers_: {
          update: kube.Container('update') {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.kubectl,
            command: [ '/script/sync-secret.sh' ],
            volumeMounts_: {
              script: {
                mountPath: '/script',
              },
            },
          },
        },
        volumes_: {
          script: {
            secret: {
              secretName: syncScript.metadata.name,
              defaultMode: 504,  // 0770
            },
          },
        },
      },
    },
  },
};

[
  jobSA,
  jobRole,
  jobRoleBinding,
  cleanJob,
  syncScript,
  syncJob,
]
