# bundle exec rails runner plugins/redmine_xls_export/test/reload_smoke.rb
# Restrict plugin reinitialization to this plugin in this runner process.
raise 'Use development or test' unless Rails.env.development? || Rails.env.test?
STDOUT.sync = true
Redmine::PluginLoader.singleton_class.prepend(Module.new do
  def directories
    super.select {|directory| File.basename(directory.to_s) == 'redmine_xls_export'}
  end
end)
3.times do |iteration|
  Rails.application.reloader.reload!
  controller = XlsExportController.new
  raise 'Export module missing' unless controller.respond_to?(:issues_to_xls2)
  listeners = Redmine::Hook.listeners.count {|listener| listener.class.name == 'XlsExportHooks'}
  raise "Expected one hook listener, got #{listeners}" unless listeners == 1
  raise 'XLS MIME type missing' unless Mime::Type.lookup_by_extension(:xls)
  raise 'ZIP exporter missing' unless Zip::OutputStream.respond_to?(:write_buffer)
  puts "PASS: reload #{iteration + 1}: controller, export module, one hook, XLS and ZIP"
end
