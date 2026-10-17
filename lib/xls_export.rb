require 'spreadsheet'
require 'nokogiri'

# Required by Zeitwerk for lib/xls_export.rb.
module XlsExport
  class ColumnLimitError < StandardError; end
end

module Redmine
  module Export
    module XLS
      XLS_ROWS = 65_535 # One row is reserved for the header.
      XLS_COLUMNS = 256
      XLS_TEXT_LENGTH = 32_767

      module StripHTML
        def strip_html(text, options)
          return text.to_s unless options[:strip_html_tags] == '1'

          document = Nokogiri::HTML.fragment(text.to_s)
          document.css('br').each {|node| node.replace("\n")}
          document.text
        end
      end
      include StripHTML

      def init_date_formats(options)
        {
          created_on: options[:created_format].presence || l(:default_created_format),
          updated_on: options[:updated_format].presence || l(:default_updated_format),
          start_date: options[:start_date_format].presence || l(:default_start_date_format),
          due_date: options[:due_date_format].presence || l(:default_due_date_format),
          closed_on: options[:closed_date_format].presence || l(:default_closed_date_format)
        }
      end

      def create_issue_columns(project, query, options)
        columns = (options[:query_columns_only] == '1' ? query.columns : query.available_columns).dup
        controls = {description: :description, relations: :relations, attachments: :attachments,
                    watcher_users: :watchers, spent_hours: :time, total_spent_hours: :time}
        columns.reject! {|column| controls[column.name] && options[controls[column.name]] != '1'}
        # Explicit options also work when their columns are not selected in the list.
        {description: :description, relations: :relations, attachments: :attachments,
         watcher_users: :watchers, spent_hours: :time}.each do |name, setting|
          column = query.available_columns.find {|c| c.name == name}
          columns << column if column && options[setting] == '1' && columns.none? {|c| c.name == name}
        end
        columns.unshift(QueryColumn.new(:id, caption: '#')) unless columns.any? {|c| c.name == :id}
        columns << QueryColumn.new(:xls_journal, caption: :label_plugin_xlse_field_journal) if options[:journal] == '1'
        columns
      end

      def localtime(datetime)
        return unless datetime

        (User.current.time_zone ? datetime.in_time_zone(User.current.time_zone) : datetime.localtime).to_time
      end

      def xls_cell_value(value)
        case value
        when ActiveSupport::TimeWithZone then value.to_time
        when Time, Date, Numeric, Spreadsheet::Link then value
        when Array then value.map {|item| xls_cell_value(item).to_s}.join("\n")[0, XLS_TEXT_LENGTH]
        else value.to_s.delete("\u0000")[0, XLS_TEXT_LENGTH]
        end
      end

      def issue_column_value(column, issue, options)
        case column.name
        when :id
          Spreadsheet::Link.new(url_for(controller: 'issues', action: 'show', id: issue.id, only_path: false), issue.id.to_s)
        when :description
          strip_html(issue.description, options).delete("\r")
        when :parent
          issue.parent&.visible? ? issue.parent : ''
        when :done_ratio
          issue.done_ratio.to_f / 100
        when :relations
          issue.relations.select {|relation| relation.other_issue(issue)&.visible?}.map do |relation|
            other = relation.other_issue(issue)
            "#{l(relation.label_for(issue))} #{other.tracker} ##{other.id}"
          end.join("\n")
        when :watcher_users
          User.current.allowed_to?(:view_issue_watchers, issue.project) ? issue.watcher_users.map(&:name).join("\n") : ''
        when :attachments
          issue.attachments.select(&:visible?).map(&:filename).join("\n")
        when :spent_hours, :total_spent_hours
          User.current.allowed_to?(:view_time_entries, issue.project) ? column.value(issue) : ''
        when :xls_journal
          get_visible_journals(issue).map do |journal|
            details = journal.visible_details.map {|detail| show_detail(detail, true)}
            ["#{format_time(journal.created_on)} - #{journal.user.name}", *details, journal.notes].compact.join("\n")
          end.then {|text| strip_html(text.join("\n"), options)}
        when :created_on, :updated_on, :closed_on
          localtime(column.value_object(issue))
        else
          if column.is_a?(QueryCustomFieldColumn)
            # value_object enforces per-project custom field visibility.
            raw = column.value_object(issue)
            values = Array(raw).map do |custom_value|
              value = column.custom_field.cast_value(custom_value.value)
              case value
              when Numeric, Date then value
              else format_object(value, false)
              end
            end
            values.size == 1 ? values.first : values
          else
            # Includes visibility checks for parent issues and association columns.
            column.value_object(issue)
          end
        end
      end

      def issues_to_xls2(issues, project, query, options = {})
        options = options.to_h.with_indifferent_access
        Spreadsheet.client_encoding = 'UTF-8'
        book = Spreadsheet::Workbook.new
        columns = create_issue_columns(project, query, options)
        raise XlsExport::ColumnLimitError if columns.size > XLS_COLUMNS

        sheets = {}
        widths = {}
        issues.each do |issue|
          group = options[:group] == '1' && query.grouped? ? query.group_by_column.group_value(issue) : l(:label_issue_plural)
          group = group.map(&:to_s).join(', ') if group.is_a?(Array)
          key = group.to_s
          sheet = sheets[key]
          if sheet.nil? || sheet.row_count > XLS_ROWS
            sheet = book.create_worksheet(name: unique_sheet_name(book, key.presence || l(:label_none)))
            sheets[key] = sheet
            widths[sheet] = init_header_columns(query, sheet, columns, init_date_formats(options))
          end
          row = sheet.row(sheet.row_count)
          columns.each_with_index do |column, index|
            value = xls_cell_value(issue_column_value(column, issue, options))
            row[index] = value
            widths[sheet][index] = [widths[sheet][index], get_value_width(value)].max
            if value.is_a?(Spreadsheet::Link)
              row.set_format(index, Spreadsheet::Format.new(color: :blue, underline: :single))
            end
          end
        end
        widths.each {|sheet, values| update_sheet_formatting(sheet, values)}
        if sheets.empty?
          book.create_worksheet(name: l(:label_issue_plural)).row(0).replace([l(:label_no_data)])
        end
        if options[:journal_worksheets] == '1'
          issues.each {|issue| journal_details_to_xls(issue, options, book)}
        end
        write_xls(book)
      end

      def get_visible_journals(issue)
        issue.visible_journals_with_index.sort_by {|journal| [journal.created_on, journal.id]}
      end

      def journal_details_to_xls(issue, options, book_to_add = nil)
        journals = get_visible_journals(issue)
        return if journals.empty?

        options = options.to_h.with_indifferent_access
        book = book_to_add || Spreadsheet::Workbook.new
        journals.each_slice(XLS_ROWS) do |slice|
          sheet = book.create_worksheet(name: unique_sheet_name(book, "#{issue.id} - Journal"))
          headers = [l(:plugin_xlse_field_issue_id), '#', l(:field_updated_on), l(:field_user), l(:label_details), l(:field_notes)]
          sheet.row(0).replace(headers)
          widths = headers.map {|header| get_value_width(header)}
          sheet.column(2).default_format = Spreadsheet::Format.new(number_format: init_date_formats(options)[:updated_on])
          slice.each_with_index do |journal, index|
            details = journal.visible_details.map {|detail| show_detail(detail, true)}.join("\n")
            values = [issue.id, journal.indice, localtime(journal.created_on), journal.user.name,
                      strip_html(details, options), strip_html(journal.notes, options)].map {|v| xls_cell_value(v)}
            sheet.row(index + 1).replace(values)
            values.each_with_index {|value, col| widths[col] = [widths[col], get_value_width(value)].max}
          end
          update_sheet_formatting(sheet, widths)
        end
        write_xls(book) unless book_to_add
      end

      def init_header_columns(query, sheet, columns, date_formats)
        sheet.row(0).replace(columns.map(&:caption))
        columns.each_with_index do |column, index|
          format = case column.name
                   when :id then '0'
                   when :done_ratio then '0%'
                   when :estimated_hours, :total_estimated_hours, :spent_hours, :total_spent_hours then '0.0'
                   else date_formats[column.name]
                   end
          if column.is_a?(QueryCustomFieldColumn)
            format = {'int' => '0', 'float' => '0.00', 'date' => date_formats[:start_date]}[column.custom_field.field_format]
          end
          sheet.column(index).default_format = Spreadsheet::Format.new(number_format: format) if format
        end
        columns.map {|column| get_value_width(column.caption) * 1.1}
      end

      def update_sheet_formatting(sheet, widths)
        widths.each_with_index do |width, index|
          sheet.column(index).width = [width, 60].min
          format = sheet.column(index).default_format.dup
          format.text_wrap = true if width > 60
          sheet.column(index).default_format = format
          sheet.row(0).set_format(index, Spreadsheet::Format.new(weight: :bold, pattern: 1,
                                    pattern_fg_color: :gray, color: :white, text_wrap: true))
        end
      end

      def get_value_width(value)
        return 20 if value.is_a?(Date) || value.is_a?(Time)

        value.to_s.split("\n", -1).map {|line| line.length + 2}.max || 2
      end

      def pretty_xls_tab_name(name)
        name.to_s.gsub(/[\\\/\[\]?*:"'\p{Cntrl}]/, '_')[0, 31]
      end

      def unique_sheet_name(book, name)
        base = pretty_xls_tab_name(name).presence || l(:label_none)
        candidate = base
        index = 1
        while book.worksheets.any? {|sheet| sheet.name.casecmp?(candidate)}
          index += 1
          suffix = " (#{index})"
          candidate = "#{base[0, 31 - suffix.length]}#{suffix}"
        end
        candidate
      end

      def init_status_histories_book
        book = Spreadsheet::Workbook.new
        [book, book.create_worksheet(name: 'Status histories')]
      end

      def add_columns_header_for_status_histories(sheet)
        headers = ['#', l(:field_project), l(:field_author), l(:plugin_xlse_field_actor),
                   l(:field_assigned_to), l(:plugin_xlse_field_issue_created_on), l(:field_updated_on),
                   l(:plugin_xlse_field_status_from), l(:plugin_xlse_field_status_to)]
        sheet.row(0).replace(headers)
        headers.map {|header| get_value_width(header)}
      end

      def status_histories_columns_format(sheet, options)
        dates = init_date_formats(options)
        {0 => '0', 5 => dates[:created_on], 6 => dates[:updated_on]}.each do |index, format|
          sheet.column(index).default_format = Spreadsheet::Format.new(number_format: format)
        end
      end

      def hash_issue_statuses
        IssueStatus.pluck(:id, :name).to_h.transform_keys(&:to_s)
      end

      def get_issue_status(id, statuses)
        statuses.fetch(id.to_s, id.to_s)
      end

      def extract_status_histories(sheet, widths, issues)
        statuses = hash_issue_statuses
        issues.each do |issue|
          # Use the same journal/detail visibility rules as the issue page.
          updates = get_visible_journals(issue).map do |journal|
            [journal, journal.visible_details.select {|detail| detail.property == 'attr' && %w(status_id assigned_to_id).include?(detail.prop_key)}]
          end.reject {|_, details| details.empty?}
          initial_status = updates.flat_map(&:last).find {|detail| detail.prop_key == 'status_id'}
          initial_assignee = updates.flat_map(&:last).find {|detail| detail.prop_key == 'assigned_to_id'}
          status = initial_status ? initial_status.old_value : issue.status_id
          assignee = initial_assignee ? initial_assignee.old_value : issue.assigned_to_id
          updates.each do |journal, details|
            status_change = details.find {|detail| detail.prop_key == 'status_id'}
            assignee_change = details.find {|detail| detail.prop_key == 'assigned_to_id'}
            old_status = status
            status = status_change.value if status_change
            assignee = assignee_change.value if assignee_change
            assignee_name = assignee.present? ? (Principal.find_by(id: assignee)&.name || "##{assignee}") : ''
            if sheet.row_count > XLS_ROWS
              sheet = sheet.workbook.create_worksheet(name: unique_sheet_name(sheet.workbook, 'Status histories'))
              widths = add_columns_header_for_status_histories(sheet)
              status_histories_columns_format(sheet, @status_history_options || {})
            end
            values = [issue.id, issue.project.name, issue.author.name, journal.user.name, assignee_name,
                      localtime(issue.created_on), localtime(journal.created_on),
                      get_issue_status(old_status, statuses), get_issue_status(status, statuses)].map {|v| xls_cell_value(v)}
            sheet.row(sheet.row_count).replace(values)
            values.each_with_index {|value, index| widths[index] = [widths[index], get_value_width(value)].max}
            update_sheet_formatting(sheet, widths)
          end
        end
        widths
      end

      def status_histories_to_xls(issues, options = {})
        options = options.to_h.with_indifferent_access
        @status_history_options = options
        book, sheet = init_status_histories_book
        widths = add_columns_header_for_status_histories(sheet)
        status_histories_columns_format(sheet, options)
        extract_status_histories(sheet, widths, issues)
        update_sheet_formatting(sheet, widths)
        write_xls(book)
      ensure
        @status_history_options = nil
      end

      def write_xls(book)
        stream = StringIO.new(''.b)
        book.write(stream)
        stream.string
      end
    end
  end
end
