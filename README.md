# XLS Export for Redmine 6.1

Export Redmine issue lists as Excel **.xls** workbooks, including descriptions, custom fields, journals, watchers, relations and spent time. Download attachments, individual journal workbooks and status histories together in a ZIP archive.

This fork is maintained for Redmine 6.1 by **[SaaS-Secure.com, S. Ruttloff](https://www.saas-secure.com/)**. It is based on the original plugin by **Vitaly Klimov**, the [two-pack fork](https://github.com/two-pack/redmine_xls_export) and the [EEA fork](https://github.com/eea/redmine_xls_export).

**Version: 1.0.0.** Validated locally with Redmine **6.1.2-stable**, Rails **7.2.3**, Ruby **3.3.7**, MySQL **8.4.11**, Spreadsheet **1.3.5** and Rubyzip **2.4.1**. The supported target is **Redmine 6.1.x**; other Redmine versions and database adapters have not been confirmed. See the [validation report](doc/REDMINE_6_1_VALIDATION.md) and [changelog](CHANGELOG.md).

## Features

- **Quick export:** one click using the administrator's defaults.
- **Detailed export:** choose options separately for each download.
- Export all available columns or the query's selected columns, with an issue ID hyperlink.
- Keep the current query's filters, sorting, selected columns and grouping.
- Include descriptions, visible custom fields, relations, watchers, spent time and attachment names.
- Include journals in an issue column, separate worksheets, or individual XLS files.
- Export status and assignee changes in a separate status history workbook.
- Split grouped results into uniquely named worksheets.
- Preserve native numbers, percentages and dates; configure Excel date formats.
- Strip HTML tags from descriptions and journals when desired.
- Include attachment files in ZIP archives, preserving Unicode and duplicate filenames.
- English and German labels; existing translations for other languages are preserved.

## Requirements

- Redmine **6.1.x** with the Ruby/Rails versions supported by that release.
- The **spreadsheet** gem, installed through the plugin's Gemfile.
- **Rubyzip**, already provided by Redmine 6.1. The obsolete `zip-zip` gem is no longer needed.
- A backup before installation or upgrade.

No additional plugin, database migration or project module is required.

## Installation

Use the directory name **redmine_xls_export**:

```sh
cd /path/to/redmine/plugins
git clone --branch v1.0.0 https://github.com/sruttloff/redmine_xls_export.git redmine_xls_export
cd /path/to/redmine
bundle install
```

If your installation uses precompiled assets, rebuild them:

```sh
bundle exec rake assets:precompile RAILS_ENV=production
```

Restart the Redmine application server using the appropriate command for your deployment, such as Puma under systemd, Passenger or Docker.

For an upgrade, back up the installation, fetch and check out the desired tag, then repeat the gem, asset and restart steps. Existing plugin settings are retained. The old `export_attachments` Bundler group is no longer used.

## Configuration and permissions

Open **Administration → Plugins → Issues XLS export → Configure**. Saved values are used by Quick export and initialize the Detailed form.

Users need Redmine's **View issues** permission. Exports follow Redmine's project, issue and custom field visibility. Private notes follow the same rules as the issue history. Watchers require `view_issue_watchers`; spent time requires `view_time_entries` and includes only visible time entries.

There are no additional plugin permissions. Only administrators can change the defaults.

## Usage

1. Open a project's **Issues** list or the global issue list.
2. Apply the desired filters, columns, sorting and grouping.
3. At the bottom, use **XLS export: Quick** or **Detailed**.
4. For Detailed export, choose options and press **Export**. Change options and download again from the same form.
5. Open the XLS file in an application supporting Excel 97–2003 workbooks, or extract the ZIP archive first.

### Export options

| Option | Result |
| --- | --- |
| Selected columns only | Start with the query's selected columns; otherwise use all available columns. The issue ID is always included. |
| Descriptions, relations, watchers, spent time, attachment list | Include that information when enabled and permitted. These switches also control those columns if selected in the query. |
| Journal entries | Add visible history as a column in the issue sheet. |
| Journal worksheets | Add a worksheet for each issue with visible journals. |
| Split by grouping criteria | Use the issue list's grouping, such as category, project or assignee. |
| Strip HTML tags | Convert descriptions/journals to plain text and preserve `<br>` line breaks. Markdown and Textile are not rendered. |
| Suggest export name | Prefix the suffix with the date and project name. Otherwise use the suffix directly. |
| Override export limit | A positive number replaces Redmine's issue export limit; `0` uses Redmine's setting. |
| Export issues starting from | Skip this many matching issues; the offset is zero-based. Negative values act as zero. |

Date fields use **Excel number formats**, for example `dd.mm.yyyy` or `dd.mm.yyyy hh:mm:ss`. Timestamps use the current user's time zone. Empty format fields fall back to localized defaults.

### ZIP contents

Selecting **Export attachments**, **Issues journals as separate files**, or **Export status histories** produces a ZIP archive:

```text
<export-name>.xls
attachments/<issue-id>/<original-filename>
journals/<issue-id>_journal_details.xls
status_histories.xls
```

Only selected extras are present. Issues without visible journals have no journal file. Duplicate attachment names receive a numeric suffix. Non-ASCII names remain Unicode. Missing storage files produce a text notice under `missing_attachments/<issue-id>/`.

The status history includes issue, project, author, actor, assignee, creation/update timestamps and status transitions. It follows visible journal details; deleted assignees are represented by their ID.

## Changes for Redmine 6.1

- Use Redmine 6.1 IssueQuery APIs and preserve query context.
- Replace obsolete ZIP APIs and Rails 2/3 compatibility branches.
- Correct missing/duplicate columns, journal options and selected-column formatting.
- Enforce visibility for private parents, notes, custom fields, relations, watchers and time entries.
- Handle worksheet/attachment name collisions, empty results and XLS boundaries.
- Enable repeated downloads from the same form.
- Complete German labels and check Rails/Zeitwerk reloading.

## Validation and development

Run from the Redmine root in a migrated development/test installation with default data:

```sh
bundle exec rake zeitwerk:check
bundle exec rails runner plugins/redmine_xls_export/test/compatibility_smoke.rb
bundle exec rails runner plugins/redmine_xls_export/test/reload_smoke.rb
```

The compatibility checks make real Rails requests as a temporary non-admin user, parse generated workbooks/archives and roll back their records. See [test instructions](test/README.md). Browser validation uses a separate test project and real downloads. GitHub Actions is configured for Redmine 6.1.2, Ruby 3.3 and MySQL 8.4.

### Format limits

This plugin writes **XLS**, not XLSX. A sheet supports 65,536 rows including its header, and 256 columns. Additional rows are split into new worksheets. For more than 256 columns, select fewer columns in Detailed export. Worksheet names are limited to 31 characters and made unique. Cell text is truncated at 32,767 characters.

Exports are generated in memory. For large data sets/attachments, set an export limit and download successive batches using the offset. Desktop spreadsheet applications were not used for visual verification; validation reads the binary files with the Spreadsheet library.

## More plugins from SaaS-Secure.com

- **[Redmine UX Toolkit](https://www.saas-secure.com/online-services/redmine-ux-toolkit.html)** – Interface improvements, dashboards, checklists, templates, reminders and administration tools.
- **[SCM Creator for Redmine](https://www.saas-secure.com/online-services/redmine-scm.html)** – Repository management for Git, Subversion, Mercurial, Bazaar and GitHub.
- **[Redcase for Redmine 6.1](https://github.com/sruttloff/redcase)** – Test case management, execution and reports.

These plugins are optional. For hosting and services, visit **[www.saas-secure.com](https://www.saas-secure.com/)**.

## Support and credits

For this fork, use the [GitHub repository](https://github.com/sruttloff/redmine_xls_export) or contact [SaaS-Secure.com](https://www.saas-secure.com/). Include Redmine/Ruby/Rails versions, selected export options and reproducible steps.

- Original plugin: **Vitaly Klimov**, [Redmine plugin page](https://www.redmine.org/plugins/redmine_xls_export).
- Features and translations: **two-pack and contributors**.
- Redmine 6 adaptation: **EEA and contributors**.
- Redmine 6.1 maintenance: **SaaS-Secure.com, S. Ruttloff**.

The inherited [README.textile](README.textile) contains historical release notes.

## License

**GNU General Public License, version 2 or later (GPL-2.0-or-later)**. Original notices remain in [COPYRIGHT.txt](COPYRIGHT.txt); see [GPL.txt](GPL.txt).
