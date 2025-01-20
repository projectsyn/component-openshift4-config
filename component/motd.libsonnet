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

[ motdCM ]
