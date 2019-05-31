include Nginx::Cookbook::Helpers

property :repo_source, String, equal_to: %w( epel nginx passenger)
property :package_name, String, default: lazy { nginx_default_package_name }
property :default_site_enabled, [true, false], default: true
property :log_dir, String, default: lazy { nginx_log_dir }


action :install do
  case new_resource.repo_source
  when 'epel'
    if platform_family?('rhel')
      include_recipe 'yum-epel'
    else
      Chef::Log.warn('EPEL installations are only available on RHEL family platforms')
    end
  when 'nginx'
    include_recipe 'nginx::repo'
  when 'passenger'
    if platform_family?('debian')
      package 'ca-certificates'

      apt_repository 'phusionpassenger' do
        uri 'https://oss-binaries.phusionpassenger.com/apt/passenger'
        distribution node['lsb']['codename']
        components %w(main)
        deb_src true
        keyserver 'keyserver.ubuntu.com'
        key '561F9B9CAC40B2F7'
      end
    else
      Chef::Log.warn('Passenger installations are only available on Debian family platforms')
    end
  end

  package new_resource.package_name do
    # notifies :reload, 'ohai[reload_nginx]', :immediately if node['nginx']['ohai_plugin_enabled']
  end

  directory node['nginx']['dir'] do
    mode      '0755'
    recursive true
  end

  directory new_resource.log_dir do
    mode      node['nginx']['log_dir_perm']
    owner     node['nginx']['user']
    action    :create
    recursive true
  end

  directory 'pid file directory' do
    path lazy { File.dirname(pidfile_location) }
    mode      '0755'
    recursive true
  end

  %w(sites-available sites-enabled conf.d streams-available streams-enabled).each do |leaf|
    directory File.join(node['nginx']['dir'], leaf) do
      mode '0755'
    end
  end

  if !node['nginx']['default_site_enabled'] && platform_family?('rhel', 'fedora', 'amazon')
    %w(default.conf example_ssl.conf).each do |config|
      file "/etc/nginx/conf.d/#{config}" do
        action :delete
      end
    end
  end

  %w(nxensite nxdissite nxenstream nxdisstream).each do |nxscript|
    template "#{node['nginx']['script_dir']}/#{nxscript}" do
      source "#{nxscript}.erb"
      mode   '0755'
    end
  end

  template 'nginx.conf' do
    path   "#{node['nginx']['dir']}/nginx.conf"
    source node['nginx']['conf_template']
    cookbook node['nginx']['conf_cookbook']
    notifies :reload, 'service[nginx]', :delayed
    variables(lazy { { pid_file: pidfile_location } })
  end

  template "#{node['nginx']['dir']}/sites-available/default" do
    source 'default-site.erb'
    notifies :reload, 'service[nginx]', :delayed
  end

  nginx_site 'default' do
    action new_resource.default_site_enabled ? :enable : :disable
  end

  packages = value_for_platform_family(
    %w(rhel amazon) => node['nginx']['passenger']['packages']['rhel'],
    %w(fedora) => node['nginx']['passenger']['packages']['fedora'],
    %w(debian) => node['nginx']['passenger']['packages']['debian']
  )

  package packages unless packages.empty?

  gem_package 'rake' if node['nginx']['passenger']['install_rake']

  if node['nginx']['passenger']['install_method'] == 'package'
    package node['nginx']['package_name']
    package 'passenger'
  elsif node['nginx']['passenger']['install_method'] == 'source'

    gem_package 'passenger' do
      action     :install
      version    node['nginx']['passenger']['version']
      gem_binary node['nginx']['passenger']['gem_binary'] if node['nginx']['passenger']['gem_binary']
    end

    passenger_module = node['nginx']['passenger']['root']

    passenger_module += if Chef::VersionConstraint.new('>= 5.0.19').include?(node['nginx']['passenger']['version'])
                          '/src/nginx_module'
                        else
                          '/ext/nginx'
                        end

    node.run_state['nginx_configure_flags'] =
      node.run_state['nginx_configure_flags'] | ["--add-module=#{passenger_module}"]

  end

  template node['nginx']['passenger']['conf_file'] do
    source 'modules/passenger.conf.erb'
    notifies :reload, 'service[nginx]', :delayed
  end

  service 'nginx' do
    supports status: true, restart: true, reload: true
    action   [:start, :enable]
  end
end

action_class do
  include Nginx::Cookbook::Helpers
end
