require_relative '../../lib/xlse_asset_helpers'
require_relative '../../lib/xls_export'
require 'zip'

class XlsExportController < ApplicationController
  helper :queries, :issues, :custom_fields
  include QueriesHelper
  include IssuesHelper
  include CustomFieldsHelper
  include Redmine::Export::XLS

  before_action :find_optional_project_xls

  def index
    @settings = XlseAssetHelpers.settings
    if request.post?
      # Unchecked boxes are submitted as 0. Only known settings are accepted.
      submitted = params.fetch(:settings, ActionController::Parameters.new)
      @settings = @settings.merge(submitted.permit(*@settings.keys).to_h)
    end
    return unless retrieve_xls_export_data

    send_export if request.post?
  end

  def export_current
    @settings = XlseAssetHelpers.settings
    send_export if retrieve_xls_export_data
  end

  private

  def find_optional_project_xls
    @project = Project.find(params[:project_id]) if params[:project_id].present?
    deny_access unless User.current.allowed_to?(:view_issues, @project, global: @project.nil?)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def retrieve_xls_export_data
    retrieve_query
    raise ::Unauthorized if @query.persisted? && !@query.visible?
    unless @query.valid?
      @issues_export_offset = [params[:issues_export_offset].to_i, 0].max
      render :index, status: :unprocessable_entity
      return false
    end

    @issues_export_offset = [params[:issues_export_offset].to_i, 0].max
    limit = @settings['issues_limit'].to_i
    limit = Setting.issues_export_limit.to_i unless limit.positive?
    @issues = @query.issues(offset: @issues_export_offset, limit: [limit, 1].max)
    # Full exports include columns that may not be selected in the query.
    Issue.load_visible_spent_hours(@issues)
    Issue.load_visible_total_spent_hours(@issues)
    Issue.load_visible_last_updated_by(@issues)
    Issue.load_visible_last_notes(@issues)
    true
  rescue ActiveRecord::RecordNotFound
    render_404
    false
  end

  def send_export
    name = get_xls_export_name
    send_data export_to_string(name),
              type: name.last == 'zip' ? 'application/zip' : 'application/vnd.ms-excel',
              filename: "#{name.first}.#{name.last}"
  rescue XlsExport::ColumnLimitError
    @query.errors.add(:base, l(:label_plugin_xlse_too_many_columns))
    render :index, status: :unprocessable_entity
  end

  def get_xls_export_name
    suffix = @settings['export_name'].to_s.gsub(/[\\\/:*?"<>|\p{Cntrl}]/, '_').strip
    suffix = 'export' if suffix.blank? || suffix.match?(/\A\.+\z/)
    if @settings['generate_name'] == '1'
      project_name = (@project ? @project.name : l(:label_project_plural)).gsub(/[\\\/:*?"<>|\p{Cntrl}\s]/, '_')
      suffix = "#{User.current.today.strftime('%y%m%d')}_#{project_name}_#{suffix}"
    end
    zip = %w(export_attached separate_journals export_status_histories).any? {|key| @settings[key] == '1'}
    [suffix, zip ? 'zip' : 'xls']
  end

  def export_to_string(name)
    workbook = issues_to_xls2(@issues, @project, @query, @settings)
    return workbook unless name.last == 'zip'

    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("#{name.first}.xls")
      zip.write(workbook)
      @issues.each do |issue|
        if @settings['export_attached'] == '1'
          used_names = {}
          issue.attachments.select(&:visible?).sort_by {|a| [a.filename.downcase, -a.id]}.each do |attachment|
            filename = unique_attachment_name(attachment.filename, used_names)
            if File.file?(attachment.diskfile)
              zip.put_next_entry("attachments/#{issue.id}/#{filename}")
              File.open(attachment.diskfile, 'rb') {|file| IO.copy_stream(file, zip)}
            else
              zip.put_next_entry("missing_attachments/#{issue.id}/#{filename}.txt")
              zip.write("Attachment file is missing from Redmine storage: #{attachment.filename}\n")
            end
          end
        end
        if @settings['separate_journals'] == '1'
          journal = journal_details_to_xls(issue, @settings)
          if journal
            zip.put_next_entry("journals/#{issue.id}_journal_details.xls")
            zip.write(journal)
          end
        end
      end
      if @settings['export_status_histories'] == '1'
        zip.put_next_entry('status_histories.xls')
        zip.write(status_histories_to_xls(@issues, @settings))
      end
    end.string
  end

  def unique_attachment_name(original, used)
    name = original.to_s.gsub(/[\\\/\p{Cntrl}]/, '_')
    name = 'attachment' if name.blank? || name.match?(/\A\.+\z/)
    ext = File.extname(name)
    stem = File.basename(name, ext)
    candidate = name
    index = 0
    while used[candidate.downcase]
      index += 1
      candidate = "#{stem}(#{format('%02d', index)})#{ext}"
    end
    used[candidate.downcase] = true
    candidate
  end
end
