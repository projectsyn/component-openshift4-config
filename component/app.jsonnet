local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_config;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-config', 'openshift-config');

{
  'openshift4-config': app,
}
