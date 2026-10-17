# Redmine 6.1 validation

From the Redmine root, with a migrated development or test database and Redmine's default data loaded:

```sh
bundle exec rake zeitwerk:check
bundle exec rails runner plugins/redmine_xls_export/test/compatibility_smoke.rb
bundle exec rails runner plugins/redmine_xls_export/test/reload_smoke.rb
```

The compatibility script makes real Rails requests as a temporary non-admin user, reads the generated XLS workbooks and ZIP archives, checks types, contents and permissions, then rolls back its database records and removes its own attachment files. Email delivery is disabled in the runner process. The script requires at least one administrator, tracker, status and time activity, and the plugin's default settings. Use a disposable development/test installation.

The reload script isolates this plugin's reinitialization from other installed plugins. It does not change the running web server.

The inherited Rails 3/4 and Capybara tests have been replaced with these Redmine 6.1 checks. Third-party category-tree plugin integration is outside this fork's validation scope.

See [the validation report](../doc/REDMINE_6_1_VALIDATION.md) for browser coverage.
