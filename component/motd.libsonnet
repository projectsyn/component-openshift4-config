local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_config;

local messages = std.prune([ params.motd.messages[m] for m in std.objectFields(params.motd.messages) ]);
local message = std.join('\n\n', messages);

local motdCM = kube.ConfigMap('motd') {
  metadata+: {
    namespace: 'openshift',
  },
  data: {
    message: message,
  },
};

local motdTemplate = kube.ConfigMap('motd-template') {
  metadata+: {
    namespace: 'openshift',
  },
  data: {
    message: message,
  },
};

local namespace = {
  metadata+: {
    namespace: 'openshift-config',
  },
};

local motdRBAC =
  local argocd_sa = kube.ServiceAccount('motd-manager') + namespace;
  local cluster_role = kube.ClusterRole('appuio:motd-editor') {
    rules: [
      {
        apiGroups: [ 'console.openshift.io' ],
        resources: [ 'consolenotifications' ],
        verbs: [ 'get', 'list' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'configmaps' ],
        resourceNames: [ 'motd', 'motd-template' ],
        verbs: [ '*' ],
      },
    ],
  };
  local cluster_role_binding =
    kube.ClusterRoleBinding('appuio:motd-manager') {
      subjects_: [ argocd_sa ],
      roleRef_: cluster_role,
    };
  {
    argocd_sa: argocd_sa,
    cluster_role: cluster_role,
    cluster_role_binding: cluster_role_binding,
  };

local jobSpec = {
  spec+: {
    template+: {
      spec+: {
        containers_+: {
          notification: kube.Container('sync-motd') {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.oc,
            name: 'sync-motd',
            workingDir: '/export',
            command: [ '/scripts/motd_gen.sh' ],
            env_+: {
              HOME: '/export',
            },
            volumeMounts_+: {
              export: {
                mountPath: '/export',
              },
              scripts: {
                mountPath: '/scripts',
              },
            },
          },
        },
        volumes_+: {
          export: {
            emptyDir: {},
          },
          scripts: {
            configMap: {
              name: 'motd-gen',
              defaultMode: std.parseOctal('0550'),
            },
          },
        },
        serviceAccountName: motdRBAC.argocd_sa.metadata.name,
      },
    },
  },
};

local motdSync = kube.Job('sync-motd') + namespace + jobSpec {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/hook': 'PostSync',
      'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
    },
  },
};

local motdScript = kube.ConfigMap('motd-gen') + namespace {
  data: {
    'motd_gen.sh': (importstr 'scripts/motd_gen.sh'),
  },
};

local motdCronJob = kube.CronJob('sync-motd') + namespace {
  spec+: {
    failedJobsHistoryLimit: 3,
    schedule: '27 */4 * * *',
    jobTemplate+: jobSpec,
  },
};

if params.motd.include_console_notifications then
  [ motdTemplate, motdSync, motdScript, motdCronJob ] + std.objectValues(motdRBAC)
else
  if std.length(params.motd.messages) > 0 then
    [ motdCM ]
  else
    []
