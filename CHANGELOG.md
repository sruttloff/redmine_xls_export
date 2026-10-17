# Changelog

## 1.0.0 — 2026-10-17

Redmine 6.1.x release, based on EEA's 0.4.0 fork.

### Compatibility and behavior

- Use current IssueQuery filters, sorting, columns and journal visibility.
- Replace legacy ZIP compatibility with Redmine's Rubyzip dependency.
- Fix description export, duplicate columns, hidden checkbox values and the spent-time control.
- Honor disabled journal worksheets and align native numeric/date/percentage formats.
- Preserve query context and support repeated downloads without reloading.
- Handle empty results, negative/overflow offsets, worksheet collisions and XLS boundaries.
- Preserve Unicode and duplicate attachment names; report missing storage files.
- Correct status histories for assignee changes and deleted users.

### Access control

- Respect project/issue visibility in project and global exports.
- Respect private notes, custom field roles, private parents and related issue visibility.
- Restrict watchers and time values through Redmine permissions and visible time entries.
- Validate saved-query visibility and sanitize output filenames.

### Documentation and validation

- Expand installation, configuration, options, limits, credits and support documentation.
- Complete German labels.
- Replace legacy tests with rollback-based request/workbook checks and a reload check.
- Configure GitHub Actions for Redmine 6.1.2, Ruby 3.3 and MySQL 8.4.
