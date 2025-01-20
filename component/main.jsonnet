// main template for openshift4-config
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_config;

local legacyPullSecret = std.get(params, 'globalPullSecret', null);

local dockercfg = std.trace(
  'Your config for openshift4-config uses the deprecated `globalPullSecret` parameter. '
  + 'Please migrate to `globalPullSecrets`. '
  + 'See https://hub.syn.tools/openshift4-config/how-to/migrate-v1.html for details.',
  kube.Secret('pull-secret') {
    metadata+: {
      namespace: 'openshift-config',
      annotations+: {
        'argocd.argoproj.io/sync-options': 'Prune=false',
      },
    },
    stringData+: {
      '.dockerconfigjson': legacyPullSecret,
    },
    type: 'kubernetes.io/dockerconfigjson',
  }
);

// Define outputs below
{
  [if legacyPullSecret != null then '01_dockercfg']: dockercfg,
  [if legacyPullSecret == null && std.length(std.objectFields(params.globalPullSecrets)) > 0 then '99_cluster_pull_secret']:
    import 'pull-secret-sync-job.libsonnet',
  [if params.clusterUpgradeSCCPermissionFix.enabled then '02_clusterUpgradeSCCPermissionFix']:
    import 'privileged-scc.libsonnet',
  [if std.length(params.motd.messages) > 0 then '03_motd']: import 'motd.libsonnet',
}
