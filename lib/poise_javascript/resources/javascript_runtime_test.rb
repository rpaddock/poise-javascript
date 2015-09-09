#
# Copyright 2015, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider'
require 'chef/resource'
require 'poise'


module PoiseJavascript
  module Resources
    # (see JavascriptRuntimeTest::Resource)
    # @since 1.0.0
    # @api private
    module JavascriptRuntimeTest
      # A `javascript_runtime_test` resource for integration testing of this
      # cookbook. This is an internal API and can change at any time.
      #
      # @provides javascript_runtime_test
      # @action run
      class Resource < Chef::Resource
        include Poise
        provides(:javascript_runtime_test)
        actions(:run)

        attribute(:version, kind_of: String, name_attribute: true)
        attribute(:runtime_provider, kind_of: Symbol)
        attribute(:path, kind_of: String, default: lazy { default_path })

        def default_path
          ::File.join('', 'root', "javascript_test_#{name}")
        end
      end

      # The default provider for `javascript_runtime_test`.
      #
      # @see Resource
      # @provides javascript_runtime_test
      class Provider < Chef::Provider
        include Poise
        provides(:javascript_runtime_test)

        # The `run` action for the `javascript_runtime_test` resource.
        #
        # @return [void]
        def action_run
          notifying_block do
            # Top level directory for this test.
            directory new_resource.path

            # Install and log the version.
            javascript_runtime new_resource.name do
              provider new_resource.runtime_provider if new_resource.runtime_provider
              version new_resource.version
            end
            test_version

            # Create a package and test npm install.
            pkg_path = ::File.join(new_resource.path, 'pkg')
            directory pkg_path
            file ::File.join(pkg_path, 'package.json') do
              content <<-EOH
{
  "name": "mypkg",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \\"Error: no test specified\\" && exit 1"
  },
  "author": "",
  "license": "ISC",
  "dependencies": {
    "express": "4.13.3"
  },
  "devDependencies": {
    "handlebars": "4.0.2"
  }
}
EOH
            end
            npm_install pkg_path do
              notifies :create, sentinel_file('npm_install_one'), :immediately
            end
            npm_install pkg_path+'2' do
              path pkg_path
              notifies :create, sentinel_file('npm_install_two'), :immediately
            end
            test_require('express', pkg_path)
            test_require('handlebars', pkg_path)

          end
        end

        def sentinel_file(name)
          file ::File.join(new_resource.path, "sentinel_#{name}") do
            action :nothing
          end
        end

        private

        def test_version(javascript: new_resource.name)
          # Only queue up this resource once, the ivar is just for tracking.
          @javascript_version_test ||= file ::File.join(new_resource.path, 'javascript_version.js') do
            user 'root'
            group 'root'
            mode '644'
            content <<-EOH
var fs = require('fs');
fs.writeFileSync(process.argv[2], process.version);
EOH
          end

          javascript_execute "#{@javascript_version_test.path} #{::File.join(new_resource.path, 'version')}" do
            javascript javascript if javascript
          end
        end

        def test_require(name, cwd, path=name, javascript: new_resource.name)
          javascript_require_test = file ::File.join(cwd, 'javascript_require.js') do
            user 'root'
            group 'root'
            mode '644'
            content <<-EOH
var fs = require('fs');
try {
  var version = require(process.argv[2] + '/package.json').version;
  fs.writeFileSync(process.argv[3], version);
} catch(e) {
}
EOH
          end

          javascript_execute "#{javascript_require_test.path} #{name} #{::File.join(new_resource.path, "require_#{path}")}" do
            javascript javascript if javascript
            cwd cwd
          end
        end

      end
    end
  end
end
