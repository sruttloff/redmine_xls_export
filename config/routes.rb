match 'issues_xls_export', to: 'xls_export#index', via: [:get, :post]
get 'issues_xls_export_current', to: 'xls_export#export_current'
match 'projects/:project_id/issues_xls_export', to: 'xls_export#index', via: [:get, :post]
get 'projects/:project_id/issues_xls_export_current', to: 'xls_export#export_current'
