local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_config;

kube._Object('security.openshift.io/v1', 'SecurityContextConstraints', 'privileged-higher-prio') {
  metadata+: {
    labels+: {
      'app.kubernetes.io/managed-by': 'commodore',
      'app.kubernetes.io/component': 'openshift4-config',
    },
    annotations+: {
      'kubernetes.io/description': |||
        Copy of `privileged` with increased priority to be choosen over other custom SCCs.

        privileged allows access to all privileged and host features and the ability to run as any user, any group, any fsGroup, and with any SELinux context.
        WARNING: this is the most relaxed SCC and should be used only for cluster administration. Grant with caution.
      |||,
    },
  },
  allowHostDirVolumePlugin: true,
  allowHostIPC: true,
  allowHostNetwork: true,
  allowHostPID: true,
  allowHostPorts: true,
  allowPrivilegeEscalation: true,
  allowPrivilegedContainer: true,
  allowedCapabilities: [
    '*',
  ],
  allowedUnsafeSysctls: [
    '*',
  ],
  defaultAddCapabilities: null,
  fsGroup: {
    type: 'RunAsAny',
  },
  groups: [
    'system:cluster-admins',
    'system:nodes',
    'system:masters',
  ],
  priority: params.clusterUpgradeSCCPermissionFix.priority,
  readOnlyRootFilesystem: false,
  requiredDropCapabilities: null,
  runAsUser: {
    type: 'RunAsAny',
  },
  seLinuxContext: {
    type: 'RunAsAny',
  },
  seccompProfiles: [
    '*',
  ],
  supplementalGroups: {
    type: 'RunAsAny',
  },
  users: [
    'system:admin',
    'system:serviceaccount:openshift-infra:build-controller',
  ],
  volumes: [
    '*',
  ],
}
