# Run with: bundle exec rails runner plugins/redmine_xls_export/test/compatibility_smoke.rb
# Creates temporary records inside a transaction; never run against production.
require 'securerandom'
require 'tempfile'
require 'nokogiri'
require 'spreadsheet'
require 'zip'
STDOUT.sync = true
raise 'Use development or test' unless Rails.env.development? || Rails.env.test?
ActionMailer::Base.perform_deliveries = false
checks = 0
attachment_paths = []
check = lambda do |condition, message|
  raise "FAIL: #{message}" unless condition
  checks += 1
  puts "PASS: #{message}"
end
read_book = ->(body) { Spreadsheet.open(StringIO.new(body.b)) }
begin
  ActiveRecord::Base.transaction do
    suffix = SecureRandom.hex(5)
    password = SecureRandom.base64(24)
    user = User.new(login: "xls-smoke-#{suffix}", firstname: 'XLS', lastname: 'Reader',
                    mail: "#{suffix}@example.invalid", language: 'en', status: User::STATUS_ACTIVE)
    user.password = password
    user.password_confirmation = password
    user.save!
    admin = User.where(admin: true).first!
    role = Role.create!(name: "XLS smoke #{suffix}", issues_visibility: 'default',
                        permissions: [:view_issues, :view_time_entries, :view_issue_watchers])
    tracker = Tracker.first!
    projects = 2.times.map do |index|
      project = Project.create!(name: "XLS smoke #{index} #{suffix}", identifier: "xls-smoke-#{index}-#{suffix}", is_public: false)
      project.enabled_module_names = %w(issue_tracking time_tracking)
      project.trackers = [tracker]
      project
    end
    project, foreign = projects
    Member.create!(project: project, user: user, roles: [role])
    User.current = admin
    categories = ['Long/group[name] abcdefghijklmnopqrstuvwxyz A', 'Long_group_name_ abcdefghijklmnopqrstuvwxyz B'].map do |name|
      project.issue_categories.create!(name: name)
    end
    issues = 3.times.map do |i|
      Issue.create!(project: project, tracker: tracker, author: admin, subject: "XLS row #{i}",
                    description: "<b>Grüße #{i}</b><br>Zweite Zeile", start_date: Date.today, due_date: Date.today + 1,
                    done_ratio: 50, estimated_hours: 2.5, category: categories[i % 2])
    end
    issue = issues.first
    hidden = Issue.create!(project: project, tracker: tracker, author: admin, subject: 'PRIVATE ISSUE SECRET', is_private: true)
    foreign_issue = Issue.create!(project: foreign, tracker: tracker, author: admin, subject: 'FOREIGN ISSUE SECRET')
    issue.reload.update!(parent: hidden)
    IssueRelation.create!(issue_from: issue, issue_to: issues.last, relation_type: 'relates')
    hidden_relation = Issue.create!(project: project, tracker: tracker, author: admin, subject: 'PRIVATE RELATION SECRET', is_private: true)
    IssueRelation.create!(issue_from: issue, issue_to: hidden_relation, relation_type: 'relates')
    issue.add_watcher(user)
    public_note = issue.journals.create!(user: admin, notes: '<b>PUBLIC NOTE</b>')
    private_note = issue.journals.create!(user: admin, notes: 'PRIVATE NOTE SECRET', private_notes: true)
    public_note.details.create!(property: 'attr', prop_key: 'status_id', old_value: IssueStatus.first!.id.to_s, value: IssueStatus.last!.id.to_s)
    public_note.details.create!(property: 'attr', prop_key: 'assigned_to_id', old_value: '', value: '99999999')
    private_note.details.create!(property: 'attr', prop_key: 'status_id', old_value: '1', value: '999999')
    activity = TimeEntryActivity.active.first!
    TimeEntry.create!(project: project, issue: issue, user: admin, hours: 1.25, spent_on: Date.today, activity: activity)
    fields = %w(int float date list).map do |format|
      field = IssueCustomField.new(name: "XLS #{format} #{suffix}", field_format: format, is_for_all: true,
                                    visible: true, tracker_ids: [tracker.id])
      field.possible_values = ['Alpha', 'Beta'] if format == 'list'
      field.multiple = true if format == 'list'
      field.save!
      field
    end
    secret_role = Role.create!(name: "XLS secret #{suffix}", permissions: [:view_issues])
    secret = IssueCustomField.create!(name: "Hidden field #{suffix}", field_format: 'string', is_for_all: true,
                                      visible: false, role_ids: [secret_role.id], tracker_ids: [tracker.id])
    issue.reload.custom_field_values = {fields[0].id => '42', fields[1].id => '1.75', fields[2].id => '2026-10-17',
                                       fields[3].id => ['Alpha', 'Beta'], secret.id => 'CUSTOM FIELD SECRET'}
    issue.save!
    ['Grüße.txt', 'Grüße.txt', 'Grüße(01).txt'].each do |name|
      Tempfile.create(['xls-smoke', '.txt']) do |file|
        file.write('ATTACHMENT CONTENT')
        file.flush
        file.rewind
        attachment = Attachment.new(container: issue, author: admin)
        attachment.file = file
        attachment.filename = name
        attachment.save!
        attachment_paths << attachment.diskfile
      end
    end
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host! 'localhost'
    session.get '/login'
    token = Nokogiri::HTML(session.response.body).at_css('input[name="authenticity_token"]')['value']
    session.post '/login', params: {username: user.login, password: password, authenticity_token: token}
    check.call(session.response.redirect?, 'non-admin login')
    base = "/projects/#{project.id}"
    session.get "#{base}/issues", params: {set_filter: '1', f: ['status_id'], op: {status_id: '*'}, v: {status_id: []}, sort: 'id:asc'}
    list_document = Nokogiri::HTML(session.response.body)
    check.call(session.response.status == 200 && list_document.at_css('a.xls') && list_document.at_css('a.xlse'), 'ticket list contains working export links')
    check.call(list_document.at_css('a.xls')['href'].include?('sort=id'), 'export link preserves sorting explicitly')
    token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')['content']
    request = lambda do |method, path, params = {}, status = 200|
      session.public_send(method, path, params: params.merge(authenticity_token: token))
      if session.response.status != status
        puts session.response.body[0, 1000]
      end
      check.call(session.response.status == status, "#{method.upcase} #{path}: #{status} (got #{session.response.status})")
      session.response
    end
    request.call(:get, "#{base}/issues_xls_export")
    check.call(!session.response.body.include?('translation missing') && session.response.body.include?('settings_time'), 'all export controls render')
    check.call(Nokogiri::HTML(session.response.body).at_css('form.multiple-submit input[type="submit"]:not([data-disable-with])'), 'download form permits repeated submissions')
    defaults = XlseAssetHelpers.settings
    quick = request.call(:get, "#{base}/issues_xls_export_current")
    book = read_book.call(quick.body)
    check.call(book.worksheets.size == 1, 'disabled journal worksheets create no extra sheets')
    headers = book.worksheet(0).row(0).to_a
    rows = book.worksheet(0).rows.to_a
    check.call(rows.size == 4 && rows[1][0].to_s == issue.id.to_s, 'query filters, ascending sort and private issue visibility')
    text = rows.map(&:to_a).flatten.join(' ')
    check.call(text.include?('<b>Grüße 0</b>') && !text.include?('SECRET'), 'description present and private issue/custom field/parent omitted')
    check.call(headers.uniq.size == headers.size, 'no duplicate built-in columns')
    cf_index = headers.index(fields.first.name)
    check.call(rows[1][cf_index] == 42 && rows[1][headers.index(fields[1].name)] == 1.75, 'numeric custom fields keep native XLS types')
    check.call(rows[1][headers.index(fields[2].name)].is_a?(Date), 'date custom field keeps native XLS date')
    check.call(rows[1][headers.index(fields[3].name)].include?("Alpha\nBeta"), 'multi-value custom fields export all values')
    link = rows[1][0]
    check.call(link.is_a?(Spreadsheet::Link) && link.url.start_with?('http://localhost/issues/'), 'issue hyperlink is a valid absolute URL')

    options = defaults.merge('generate_name' => '0', 'export_name' => 'smoke', 'description' => '0',
                             'relations' => '0', 'watchers' => '0', 'query_columns_only' => '1')
    selection = {set_filter: '1', f: ['status_id'], op: {status_id: '*'}, v: {status_id: []},
                 c: ['subject', 'done_ratio', 'created_on'], sort: 'id:asc'}
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options))
    sheet = read_book.call(response.body).worksheet(0)
    check.call(sheet.row(0).to_a == ['#', 'Subject', '% Done', 'Created'], 'selected columns with an inserted ID align correctly')
    check.call(sheet.row(1)[2] == 0.5 && sheet.column(2).default_format.number_format == '0%', 'percentage stays numeric and format aligns')
    check.call(sheet.row(1)[3].is_a?(Date), 'created timestamp is an Excel date')
    options.merge!('issues_limit' => '1')
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options, issues_export_offset: 1))
    check.call(read_book.call(response.body).worksheet(0).row(1)[0].to_s == issues[1].id.to_s, 'offset and override export limit')
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options, issues_export_offset: -10))
    check.call(read_book.call(response.body).worksheet(0).row(1)[0].to_s == issue.id.to_s, 'negative offset is clamped to zero')
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options, issues_export_offset: 999))
    check.call(read_book.call(response.body).worksheet(0).row_count == 1, 'offset beyond results returns a valid empty workbook')
    options.merge!('issues_limit' => '0', 'description' => '1', 'journal' => '1', 'journal_worksheets' => '1',
                   'time' => '1', 'attachments' => '1', 'watchers' => '1', 'relations' => '1',
                   'strip_html_tags' => '1', 'export_attached' => '1', 'separate_journals' => '1',
                   'export_status_histories' => '1')
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options))
    check.call(response.media_type == 'application/zip' && response.body.start_with?("PK"), 'ZIP response has correct content type and signature')
    entries = {}
    Zip::File.open_buffer(StringIO.new(response.body.b)) {|zip| zip.each {|entry| entries[entry.name] = entry.get_input_stream.read}}
    check.call(entries.keys.count {|name| name.start_with?('attachments/')} == 3 && entries.values.count('ATTACHMENT CONTENT') == 3,
               'Unicode attachment names and all duplicate filenames survive ZIP export')
    check.call(entries.key?('status_histories.xls') && entries.key?("journals/#{issue.id}_journal_details.xls"), 'separate journals and status history are included')
    combined = read_book.call(entries.fetch('smoke.xls'))
    check.call(combined.worksheets.size == 2, 'inline journal worksheet added for issue with visible history')
    text = combined.worksheets.flat_map {|sheet| sheet.rows.to_a.map(&:to_a).flatten}.join(' ')
    check.call(text.include?('PUBLIC NOTE') && !text.include?('PRIVATE NOTE SECRET') && !text.include?('<b>'), 'HTML stripping and journal privacy in workbook')
    check.call(text.include?('1.25') && text.include?(user.name) && text.include?("##{issues.last.id}"), 'spent time, watchers and visible relations')
    history = read_book.call(entries.fetch('status_histories.xls')).worksheet(0)
    check.call(history.row_count == 2 && history.row(1)[4] == '#99999999', 'status history excludes private changes and handles deleted assignees')

    options = defaults.merge('group' => '1', 'generate_name' => '0', 'export_name' => 'grouped')
    response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: options, group_by: 'category'))
    grouped = read_book.call(response.body)
    names = grouped.worksheets.map(&:name)
    check.call(names.size == 2 && names.uniq.size == 2 && names.all? {|name| name.length <= 31 && !name.match?(/[\\\/\[\]?*:]/)},
               'grouping uses unique Excel-safe worksheet names')
    check.call(grouped.worksheets.sum {|sheet| sheet.row_count - 1} == 3, 'grouping keeps every issue')
    saved = IssueQuery.create!(name: "XLS saved #{suffix}", project: project, user: user,
                               column_names: [:subject], sort_criteria: [['id', 'asc']])
    response = request.call(:get, "#{base}/issues_xls_export", {query_id: saved.id})
    document = Nokogiri::HTML(response.body)
    check.call(document.at_css('input[name="c[]"][value="subject"]') && document.at_css('input[name="sort"][value="id"]'),
               'detailed form preserves saved query columns and sorting')
    private_query = IssueQuery.create!(name: "XLS private #{suffix}", project: project, user: admin, visibility: Query::VISIBILITY_PRIVATE)
    request.call(:get, "#{base}/issues_xls_export_current", {query_id: private_query.id}, 403)

    # Exercise XLS boundary handling with small limits rather than allocating 65k records.
    export_module = Redmine::Export::XLS
    old_rows = export_module::XLS_ROWS
    old_columns = export_module::XLS_COLUMNS
    begin
      export_module.send(:remove_const, :XLS_ROWS)
      export_module.const_set(:XLS_ROWS, 2)
      response = request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: defaults))
      split_book = read_book.call(response.body)
      check.call(split_book.worksheets.size == 2 && split_book.worksheets.sum {|sheet| sheet.row_count - 1} == 3,
                 'issues spill into additional sheets at the XLS row boundary')
      export_module.send(:remove_const, :XLS_COLUMNS)
      export_module.const_set(:XLS_COLUMNS, 2)
      request.call(:post, "#{base}/issues_xls_export", selection.merge(settings: defaults), 422)
      check.call(session.response.body.include?('256 columns'), 'too many columns produce an actionable validation error')
    ensure
      export_module.send(:remove_const, :XLS_ROWS)
      export_module.const_set(:XLS_ROWS, old_rows)
      export_module.send(:remove_const, :XLS_COLUMNS)
      export_module.const_set(:XLS_COLUMNS, old_columns)
    end
    request.call(:get, "/projects/#{foreign.id}/issues_xls_export_current", {}, 403)
    request.call(:get, '/projects/missing-xls-project/issues_xls_export_current', {}, 404)
    request.call(:get, '/settings/plugin/redmine_xls_export', {}, 403)
    request.call(:get, "#{base}/issues_xls_export_current", {query_id: 99999999}, 404)
    request.call(:get, "#{base}/issues_xls_export_current",
                 {set_filter: '1', f: ['created_on'], op: {created_on: '='}, v: {created_on: ['not-a-date']}}, 422)
    check.call(session.response.body.include?('errorExplanation'), 'invalid query produces a readable validation message')
    # A global export must enforce each project's visibility.
    response = request.call(:get, '/issues_xls_export_current',
                            {set_filter: '1', f: ['status_id'], op: {status_id: '*'}, v: {status_id: []}})
    text = read_book.call(response.body).worksheets.flat_map {|sheet| sheet.rows.to_a.map(&:to_a).flatten}.join(' ')
    check.call(!text.include?('FOREIGN ISSUE SECRET') && !text.include?('PRIVATE ISSUE SECRET'), 'global export enforces project and private issue visibility')
    I18n.with_locale(:de) do
      keys = I18n.t(:label_plugin_xlse_journal_worksheets)
      check.call(keys.include?('Arbeitsblätter') && I18n.t(:plugin_xlse_field_actor) == 'Geändert von', 'German labels are complete')
    end
    raise ActiveRecord::Rollback
  end
ensure
  attachment_paths.each {|path| File.delete(path) if File.file?(path)}
  User.current = nil
end
puts "SUCCESS: #{checks} compatibility checks; database changes rolled back."
