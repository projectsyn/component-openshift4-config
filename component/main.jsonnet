// main template for openshift4-config
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_config;

local dockercfg = kube.Secret(params.dockerCredentials.secretName) {
  metadata+: {
    namespace: params.namespace,
  },
  stringData+: {
    '.dockerconfigjson': params.dockerCredentials.dockerconfigjson,
  },
};

// Define outputs below
{
  '01_dockercfg': dockercfg,
}
