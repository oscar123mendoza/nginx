nginx_site 'Disable default site' do
  site_name 'default'
  action :disable
end

nginx_site 'Enable the test_site' do
  template 'site.erb'
  site_name 'test_site'
  action :enable
end
