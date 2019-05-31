include_recipe 'nginx::ohai_plugin' if node['nginx']['ohai_plugin_enabled']
