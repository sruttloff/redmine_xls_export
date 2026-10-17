require_relative 'xlse_asset_helpers'

class XlsExportHooks < Redmine::Hook::ViewListener
  def view_issues_index_bottom(context = {})
    query = context[:query]
    return unless query&.valid? && context[:issues].present?

    options = query.as_params.merge(controller: 'xls_export', project_id: context[:project])
    quick = link_to(l(:label_plugin_xlse_export_format_quick), options.merge(action: 'export_current'),
                    class: 'xls', rel: 'nofollow', title: l(:label_plugin_xlse_export_format_quick_tooltip))
    detailed = link_to(l(:label_plugin_xlse_export_format_detailed), options.merge(action: 'index'),
                       class: 'xlse', title: l(:label_plugin_xlse_export_format_detailed_tooltip))
    stylesheet_link_tag('xls_export.css', plugin: XlseAssetHelpers::PLUGIN_NAME, media: 'screen') +
      content_tag(:p, safe_join([l(:label_plugin_xlse_export_format), content_tag(:span, quick),
                                content_tag(:span, detailed)], ' '), class: 'other-formats')
  end
end
