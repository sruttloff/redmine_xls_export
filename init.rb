require 'redmine'
require_relative 'lib/xlse_asset_helpers'
require 'zip'

unless Redmine::Plugin.registered_plugins.keys.include?(XlseAssetHelpers::PLUGIN_NAME)
  Redmine::Plugin.register XlseAssetHelpers::PLUGIN_NAME do
    name 'Issues XLS export'
    author 'Vitaly Klimov; two-pack; EEA; SaaS-Secure.com, S. Ruttloff'
    description 'Export issues to XLS files including journals, descriptions, etc. This plugin requires spreadsheet gem.'
    version '1.0.0'
    url 'https://github.com/sruttloff/redmine_xls_export'
    author_url 'https://www.saas-secure.com/'
    
    settings(:partial => 'settings/xls_export_settings',
             :default => {
               'relations' => '1',
               'watchers' => '1',
               'description' => '1',
               'journal' => '0',
               'journal_worksheets' => '0',
               'time' => '0',
               'attachments' => '0',
               'query_columns_only' => '0',
               'group' => '0',
               'generate_name' => '1',
               'strip_html_tags' => '0',
               'export_attached' => '0',
               'separate_journals' => '0',
               'export_status_histories' => '0',
               'issues_limit' => '0',
               'export_name' => 'issues_export',
               'created_format' => "dd.mm.yyyy hh:mm:ss",
               'updated_format' => "dd.mm.yyyy hh:mm:ss",
               'start_date_format' => "dd.mm.yyyy",
               'due_date_format' => "dd.mm.yyyy",
               'closed_date_format' => "dd.mm.yyyy hh:mm:ss"
             })

    requires_redmine :version_or_higher => '6.1.0'
  end

end
require_relative 'lib/xls_export_hooks'
unless Redmine::Hook.listeners.any? {|listener| listener.is_a?(XlsExportHooks)}
  Redmine::Hook.add_listener(XlsExportHooks)
end

Mime::Type.register('application/vnd.ms-excel', :xls) unless Mime::Type.lookup_by_extension(:xls)
Mime::Type.register('application/zip', :zip) unless Mime::Type.lookup_by_extension(:zip)
