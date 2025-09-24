set theTaskName to "%s"
set theNote to "%s"
set theProjectName to "%s"
tell application "OmniFocus"
    tell default document
        set theTask to missing value
        try
            set theProj to first flattened project whose name is theProjectName
            set theTask to make new task with properties {name:theTaskName, note:theNote} at end of tasks of theProj
        on error
            set theTask to make new inbox task with properties {name:theTaskName, note:theNote}
        end try
    end tell
end tell
