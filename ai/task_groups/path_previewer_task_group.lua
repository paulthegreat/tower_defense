local PathPreviewerTaskGroup = class()
PathPreviewerTaskGroup.name = 'preview path'
PathPreviewerTaskGroup.does = 'stonehearth:compelled_behavior'
PathPreviewerTaskGroup.priority = 1

return stonehearth.ai:create_task_group(PathPreviewerTaskGroup)
         :declare_permanent_task('tower_defense:path_previewer_follow_path', {}, 1)